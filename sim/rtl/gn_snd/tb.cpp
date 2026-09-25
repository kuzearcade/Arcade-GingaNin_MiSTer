// The sound board alone (gn_sound: 6809, PTM, latch/NMI) against MAME's bus
// trace (sim/oracle/gn_sndtrace.lua). The main CPU's latch writes are replayed
// at MAME's times; every 6809 write to the PTM, the Y8950 and the YM2149 is
// logged as "t_ns dev W offset data", MAME's format, for tools/gn_sndcmp.py.
//   ./obj_dir/Vgn_sound SND_BIN MAME_TRACE OUT_TRACE MS [ADPCM_BIN WAV_OUT]
// With ADPCM_BIN the Y8950's samples are served (8-clock latency) and the mixed
// output is written to WAV_OUT as raw int16 mono at 48 kHz, with WAV_OUT.opl (the
// Y8950 alone) and WAV_OUT.psg (the YM2149 alone, as the mixer adds it).
#include "Vgn_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 5) { fprintf(stderr, "usage: SND_BIN MAME_TRACE OUT_TRACE MS\n"); return 1; }
	std::vector<uint8_t> rom(0x10000);
	FILE *f = fopen(argv[1], "rb"); if (!f || fread(rom.data(), 1, 0x10000, f) != 0x10000) { fprintf(stderr, "no rom\n"); return 1; } fclose(f);
	// GN_WARP=1: replay each command at its offset from the preceding PTM
	// release (CR1 = 0x92) in MAME, anchored to the RTL's own release times,
	// which removes the IRQ-latency drift (GN-4) from the comparison
	bool warp = getenv("GN_WARP") != nullptr;
	struct Cmd { double t; unsigned d; int k; double off; };
	std::vector<Cmd> cmds;
	std::vector<double> rel_mame;
	f = fopen(argv[2], "r"); char line[256];
	while (fgets(line, sizeof line, f)) {
		double t; char dev[16], rw[4]; unsigned off, d;
		if (sscanf(line, "%lf %15s %3s %x %x", &t, dev, rw, &off, &d) != 5) continue;
		if (!strcmp(dev, "ptm") && rw[0] == 'W' && off == 0 && d == 0x92) rel_mame.push_back(t);
		if (!strcmp(dev, "cmd")) {
			int k = (int)rel_mame.size() - 1;
			cmds.push_back({t, d & 0xFF, k, k >= 0 ? t - rel_mame[k] : t});
		}
	}
	fclose(f);
	FILE *out = fopen(argv[3], "w");
	std::vector<uint8_t> adpcm(0x20000, 0);
	FILE *wav = nullptr, *wav_opl = nullptr, *wav_psg = nullptr;
	if (argc > 6) {
		FILE *a = fopen(argv[5], "rb"); if (!a || fread(adpcm.data(), 1, adpcm.size(), a) != adpcm.size()) return 1; fclose(a);
		wav = fopen(argv[6], "wb");
		wav_opl = fopen((std::string(argv[6]) + ".opl").c_str(), "wb");
		wav_psg = fopen((std::string(argv[6]) + ".psg").c_str(), "wb");
	}
	int acnt = -1; uint64_t next_audio = 0;
	double end_ns = atof(argv[4]) * 1e6;
	Vgn_sound *t = new Vgn_sound;
	uint64_t cyc = 0; size_t ci = 0;
	std::vector<double> rel_rtl;
	t->reset = 1; t->pause = 0; t->cmd_we = 0; t->cmd = 0;
	auto tick = [&]() {
		t->clk = 0; t->eval();
		t->rom_data = rom[t->rom_addr];
		t->adpcm_ack = 0;
		if (t->adpcm_req) { if (acnt < 0) acnt = 8; else if (acnt > 0 && --acnt == 0) { t->adpcm_data = adpcm[t->adpcm_addr & 0x1FFFF]; t->adpcm_ack = 1; acnt = -2; } }
		else acnt = -1;
		t->clk = 1; t->eval(); cyc++;
		if (wav && cyc >= next_audio) {
			next_audio += 1000;
			int16_t v = t->snd, o = t->dbg_opl, p = (int16_t)t->dbg_psg;   // already in WAV units
			fwrite(&v, 2, 1, wav); fwrite(&o, 2, 1, wav_opl); fwrite(&p, 2, 1, wav_psg);
		}
	};
	for (int i = 0; i < 2000; i++) tick();         // reset over ~37 E cycles
	t->reset = 0;
	// GN_PARK=ms: at that time park the 6809 (ss_m6809_park), freeze the board's
	// clock for 2 ms, resume; the command schedule is shifted by the frozen
	// time, so the device write sequence must come out unchanged
	t->ss_a = 0x947;                 // the state bus shows the park register S
	double park_at = getenv("GN_PARK") ? atof(getenv("GN_PARK")) * 1e6 : -1, shift = 0, held_since = -1;
	int pstate = 0;
	for (;;) {
		double ns = cyc * (1e9 / 48e6) - shift;
		if (ns > end_ns) break;
		if (park_at >= 0) {
			double wall = cyc * (1e9 / 48e6);
			if (pstate == 0 && ns >= park_at) { t->park_req = 1; pstate = 1; printf("park requested at %.3f ms\n", ns / 1e6); }
			else if (pstate == 1 && t->parked) { t->hold = 1; held_since = wall; pstate = 2; printf("parked, S=%04X, held\n", t->ss_rdata); }
			else if (pstate == 2 && wall - held_since > 2e6) { t->hold = 0; t->resume = 1; pstate = 3; }
			else if (pstate == 3 && !t->parked) { t->resume = 0; t->park_req = 0; pstate = 4; printf("resumed after %.3f ms parked\n", (wall - held_since) / 1e6); }
			if (pstate >= 1 && pstate <= 3) { tick(); shift += 1e9 / 48e6; continue; }
		}
		t->cmd_we = 0;
		if (ci < cmds.size()) {
			double due = cmds[ci].t;
			if (warp) due = cmds[ci].k < 0 ? cmds[ci].off : (cmds[ci].k < (int)rel_rtl.size() ? rel_rtl[cmds[ci].k] + cmds[ci].off : 1e30);
			if (ns >= due) { t->cmd_we = 1; t->cmd = cmds[ci].d; ci++; }
		}
		static unsigned last_a = 0xFFFFFFFF; static int nch = 0;
		static int NTR = getenv("GN_TRACE") ? atoi(getenv("GN_TRACE")) : 0;
		tick();
		if (nch < NTR && t->dbg_fallE) { printf("%8.0f ns  A=%04X %s D=%02X nmi_n=%d\n", ns, t->dbg_pc_addr, t->dbg_rnw ? "R" : "W", t->dbg_rnw ? t->dbg_di : t->dbg_wdata, t->dbg_nmi_n); nch++; }
		if (t->dbg_wr) {
			unsigned a = t->dbg_waddr, d = t->dbg_wdata;
			const char *dev = (a >= 0x800 && a <= 0x807) ? "ptm" : (a >= 0x2000 && a <= 0x2001) ? "opl" : (a >= 0x2800 && a <= 0x2801) ? "psg" : nullptr;
			if (dev && dev[1] == 't' && (a & 7) == 0 && d == 0x92) rel_rtl.push_back(ns);
			if (dev) fprintf(out, "%.0f %s W %X %X\n", ns, dev, a & (dev[0] == 'p' && dev[1] == 't' ? 7 : 1), d);
		}
	}
	fclose(out);
	if (wav) { fclose(wav); fclose(wav_opl); fclose(wav_psg); }
	printf("done: %.1f ms, %zu commands, nmi %u, irq %u, ptm writes %u, latch reads %u\n", end_ns / 1e6, ci, t->dbg_nmi, t->dbg_irq, t->dbg_ptm_writes, t->dbg_latch_reads);
	delete t;
	return 0;
}
