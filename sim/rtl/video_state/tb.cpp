// M1: gn_video renders a captured MAME state (sim/oracle/gn_capture.lua) and is
// compared with MAME's picture F+1, state F+1's palette colouring it (GN-2):
//   ./obj_dir/Vgn_video SET TRACE_DIR F [F ...]
// ROM regions come from ~/gn_images/SET/. The tile ROM ports answer after
// MP_LAT clocks (default 12), one request at a time as the engines issue them;
// MP_STALL=n adds n extra clocks to every n-th request (MP-9's stall test).
#include "Vgn_video.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
static std::vector<uint8_t> slurp(const std::string &p) {
	FILE *f = fopen(p.c_str(), "rb"); if (!f) { fprintf(stderr, "no %s\n", p.c_str()); exit(1); }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<uint8_t> v(n); if (fread(v.data(), 1, n, f) != (size_t)n) exit(1); fclose(f); return v;
}
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 4) { fprintf(stderr, "usage: SET TRACE F...\n"); return 1; }
	std::string img = std::string(getenv("HOME")) + "/gn_images/" + argv[1] + "/", tr = argv[2];
	auto bgt = slurp(img + "bgt.bin"), fgt = slurp(img + "fgt.bin"), spr = slurp(img + "spr.bin");
	auto txt = slurp(img + "text.bin"), bgm = slurp(img + "bgmap.bin");
	int LAT = getenv("MP_LAT") ? atoi(getenv("MP_LAT")) : 12, STALL = getenv("MP_STALL") ? atoi(getenv("MP_STALL")) : 0;
	Vgn_video *t = new Vgn_video;
	uint64_t cyc = 0;
	int cnt[3] = {-1, -1, -1}; unsigned nreq[3] = {0, 0, 0};
	auto row = [&](const std::vector<uint8_t> &r, uint32_t a) {
		uint32_t v = 0; for (int i = 0; i < 4; i++) v = v << 8 | (a + i < r.size() ? r[a + i] : 0); return v;
	};
	auto serve = [&](int k, uint8_t req, uint32_t addr, uint8_t &ack, uint32_t &data, const std::vector<uint8_t> &r) {
		ack = 0;
		if (req) {
			if (cnt[k] < 0) { cnt[k] = LAT + ((STALL && (++nreq[k] % STALL) == 0) ? STALL : 0); }
			else if (cnt[k] > 0 && --cnt[k] == 0) { data = row(r, addr); ack = 1; cnt[k] = -2; }
		} else cnt[k] = -1;
	};
	std::vector<uint32_t> fb(256 * 224);
	auto tick = [&]() {
		t->clk = 0; t->eval();
		uint8_t a; uint32_t d;
		a = 0; d = t->bg_data;  serve(0, t->bg_req,  t->bg_addr,  a, d, bgt); t->bg_ack = a;  t->bg_data = d;
		a = 0; d = t->fg_data;  serve(1, t->fg_req,  t->fg_addr,  a, d, fgt); t->fg_ack = a;  t->fg_data = d;
		a = 0; d = t->spr_data; serve(2, t->spr_req, t->spr_addr, a, d, spr); t->spr_ack = a; t->spr_data = d;
		t->clk = 1; t->eval(); cyc++;
		// the pixel for dot h is out 3 clocks after its read; sample it at the next dot
		static int ph = -1, pv = -1;
		static unsigned last_ov = 0;
		if (getenv("MP_OVLINES") && t->dbg_spr_overruns != last_ov) { printf("  overrun at vcount %d hcount %d\n", t->vcount, t->hcount); last_ov = t->dbg_spr_overruns; }
		if (t->ce_pix) {
			if (ph >= 0 && ph < 256 && pv >= 16 && pv < 240) fb[(pv - 16) * 256 + ph] = t->rgb;
			ph = t->hcount; pv = t->vcount;
		}
	};
	t->reset = 1; t->sel_txt = t->sel_spr = t->sel_pal = t->sel_reg = t->sel_fg = 0; t->cpu_we = 0; t->dl_we = 0;
	for (int i = 0; i < 20; i++) tick();
	// the ROM BRAMs
	for (size_t i = 0; i < txt.size(); i++) { t->dl_we = 1; t->dl_bgmap = 0; t->dl_addr = i; t->dl_data = txt[i]; tick(); }
	for (size_t i = 0; i < bgm.size(); i++) { t->dl_we = 1; t->dl_bgmap = 1; t->dl_addr = i; t->dl_data = bgm[i]; tick(); }
	t->dl_we = 0;
	t->reset = 0;
	for (int ai = 3; ai < argc; ai++) {
		int F = atoi(argv[ai]);
		char fn[512];
		snprintf(fn, sizeof fn, "%s/s%05d.bin", tr.c_str(), F);     auto st = slurp(fn);
		snprintf(fn, sizeof fn, "%s/s%05d.bin", tr.c_str(), F + 1); auto st1 = slurp(fn);
		snprintf(fn, sizeof fn, "%s/p%05d.raw", tr.c_str(), F + 1); auto pic = slurp(fn);
		auto w16 = [&](const std::vector<uint8_t> &s, int byteoff) { return (uint16_t)(s[byteoff] << 8 | s[byteoff + 1]); };
		auto cpuw = [&](int blk, int addr, uint16_t v) {
			t->sel_txt = blk == 0; t->sel_spr = blk == 1; t->sel_pal = blk == 2; t->sel_reg = blk == 3; t->sel_fg = blk == 4;
			t->cpu_addr = addr; t->cpu_we = 1; t->cpu_be = 3; t->cpu_din = v; tick();
			t->sel_txt = t->sel_spr = t->sel_pal = t->sel_reg = t->sel_fg = 0; t->cpu_we = 0;
		};
		for (int i = 0; i < 1024; i++) cpuw(0, i, w16(st, 0x0000 + 2 * i));
		for (int i = 0; i < 1024; i++) cpuw(1, i, w16(st, 0x0800 + 2 * i));
		for (int i = 0; i < 1024; i++) if (st1.size() >= 0x58A0 && (st1[0x5820 + i / 8] >> (i % 8) & 1)) cpuw(2, i, w16(st1, 0x1000 + 2 * i));
		for (int i = 0; i < 8; i++) cpuw(3, i, w16(st, 0x1800 + 2 * i));
		for (int i = 0; i < 8192; i++) cpuw(4, i, w16(st, 0x1820 + 2 * i));
		// two full frames, so every line is drawn from the loaded state
		for (long i = 0; i < 2L * 100000 * 8; i++) tick();
		int diff = 0, nb = 0;
		for (int i = 0; i < 256 * 224; i++) {
			uint32_t m = (pic[4 * i] | pic[4 * i + 1] << 8 | pic[4 * i + 2] << 16) & 0xFFFFFF;
			diff += (fb[i] & 0xFFFFFF) != m; nb += m != 0;
		}
		printf("state %d vs MAME picture %d: %d differing of %d (MAME non-black %d)  %s | spr overruns %u\n",
		       F, F + 1, diff, 256 * 224, nb, diff ? "DIFFERS" : "MATCH", t->dbg_spr_overruns);
		if (getenv("MP_PPM")) {
			FILE *p = fopen(getenv("MP_PPM"), "wb"); fprintf(p, "P6\n256 224\n255\n");
			for (int i = 0; i < 256 * 224; i++) { uint8_t c[3] = {(uint8_t)(fb[i] >> 16), (uint8_t)(fb[i] >> 8), (uint8_t)fb[i]}; fwrite(c, 1, 3, p); }
			fclose(p);
		}
		fflush(stdout);
	}
	delete t;
	return 0;
}
