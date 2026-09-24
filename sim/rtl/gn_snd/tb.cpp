// The sound board alone (gn_sound: 6809, PTM, latch/NMI) against MAME's bus
// trace (sim/oracle/gn_sndtrace.lua). The main CPU's latch writes are replayed
// at MAME's times; every 6809 write to the PTM, the Y8950 and the YM2149 is
// logged as "t_ns dev W offset data", MAME's format, for tools/gn_sndcmp.py.
//   ./obj_dir/Vgn_sound SND_BIN MAME_TRACE OUT_TRACE MS
#include "Vgn_sound.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
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
	double end_ns = atof(argv[4]) * 1e6;
	Vgn_sound *t = new Vgn_sound;
	uint64_t cyc = 0; size_t ci = 0;
	std::vector<double> rel_rtl;
	t->reset = 1; t->pause = 0; t->cmd_we = 0; t->cmd = 0;
	auto tick = [&]() {
		t->clk = 0; t->eval();
		t->rom_data = rom[t->rom_addr];
		t->clk = 1; t->eval(); cyc++;
	};
	for (int i = 0; i < 2000; i++) tick();         // reset over ~37 E cycles
	t->reset = 0;
	for (;;) {
		double ns = cyc * (1e9 / 48e6);
		if (ns > end_ns) break;
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
	printf("done: %.1f ms, %zu commands, nmi %u, irq %u, ptm writes %u, latch reads %u\n", end_ns / 1e6, ci, t->dbg_nmi, t->dbg_irq, t->dbg_ptm_writes, t->dbg_latch_reads);
	delete t;
	return 0;
}
