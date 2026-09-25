// M2: the whole board from reset against MAME (docs/PLAN.md M2).
//   ./obj_dir/Vgn_core IMAGE_DIR FRAMES
// IMAGE_DIR is ~/gn_images/<set>/ (tools/gen_gn_mra.py --images). Environment:
//   MP_TRACE=dir     compare every frame with MAME's pictures in dir (search offset)
//   MP_PLAY=1        gn_play.lua's inputs (coin 600, start 660, from 720 buttons and
//                    moves) and its lives poke (0x20058 = 3) through the RAM back door
//   MP_FRAMEDIR=dir  write each frame as fNNNNN.raw (u32 0x00RRGGBB, 256 x 224)
//   MP_WAV=file      the mixed audio, raw int16 mono at 48 kHz
//   MP_EVERY=n       status every n frames (default 60)
#include "Vgn_core.h"
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
static int env(const char *n, int d) { const char *v = getenv(n); return v ? atoi(v) : d; }
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 3) { fprintf(stderr, "usage: IMAGE_DIR FRAMES\n"); return 1; }
	std::string d = argv[1]; int frames = atoi(argv[2]);
	auto img = slurp(d + "/image.bin");
	auto bgt = slurp(d + "/bgt.bin"), fgt = slurp(d + "/fgt.bin"), spr = slurp(d + "/spr.bin"), adp = slurp(d + "/adpcm.bin");
	const char *trace = getenv("MP_TRACE"), *fdir = getenv("MP_FRAMEDIR");
	bool play = getenv("MP_PLAY") != nullptr;
	int EVERY = env("MP_EVERY", 60), F0 = 600;
	FILE *wav = getenv("MP_WAV") ? fopen(getenv("MP_WAV"), "wb") : nullptr;
	Vgn_core *t = new Vgn_core;
	uint64_t cyc = 0, next_audio = 0;
	int cnt[4] = {-1, -1, -1, -1};
	auto row = [&](const std::vector<uint8_t> &r, uint32_t a) { uint32_t v = 0; for (int i = 0; i < 4; i++) v = v << 8 | (a + i < r.size() ? r[a + i] : 0); return v; };
	std::vector<uint32_t> fb(256 * 224);
	int ph = -1, pv = -1, cur_frame = 0;
	auto tick = [&]() {
		t->clk = 0; t->eval();
		// ROM ports: held request, ack after 12 clocks
		auto serve = [&](int k, uint8_t req, uint8_t &ack) -> bool {
			ack = 0;
			if (req) { if (cnt[k] < 0) cnt[k] = 12; else if (cnt[k] > 0 && --cnt[k] == 0) { ack = 1; cnt[k] = -2; return true; } }
			else cnt[k] = -1;
			return false;
		};
		uint8_t a;
		if (serve(0, t->bg_req, a))  t->bg_data = row(bgt, t->bg_addr);   t->bg_ack = a;
		if (serve(1, t->fg_req, a))  t->fg_data = row(fgt, t->fg_addr);   t->fg_ack = a;
		if (serve(2, t->spr_req, a)) t->spr_data = row(spr, t->spr_addr); t->spr_ack = a;
		if (serve(3, t->adpcm_req, a)) t->adpcm_data = adp[t->adpcm_addr & 0x1FFFF]; t->adpcm_ack = a;
		t->clk = 1; t->eval(); cyc++;
		if (t->ce_pix) {
			if (ph >= 0 && ph < 256 && pv >= 16 && pv < 240) fb[(pv - 16) * 256 + ph] = t->rgb;
			ph = t->hcount; pv = t->vcount;
		}
		// MP_WRLOG=a,b: log CPU writes into video memory during visible lines of frames a..b
		static int wl_a = -1, wl_b = -1; static uint32_t last_wa = 0xFFFFFFFF;
		if (wl_a < 0 && getenv("MP_WRLOG")) sscanf(getenv("MP_WRLOG"), "%d,%d", &wl_a, &wl_b);
		if (wl_a >= 0 && cur_frame >= wl_a && cur_frame <= wl_b && (getenv("MP_WRALL") || (t->vcount >= 16 && t->vcount < 240))) {
			uint32_t aa = t->dbg_addr;
			if (aa >= 0x30000 && aa < 0x70000 && aa != last_wa && t->dbg_wr) { printf("  wr f%d line %d %06x %04x %d\n", cur_frame, t->vcount, aa, t->dbg_wdata, t->dbg_be); last_wa = aa; }
		}
				if (wav && cyc >= next_audio) { next_audio += 1000; int16_t s = t->snd; fwrite(&s, 2, 1, wav); }
	};
	t->reset = 1; t->pause = 0; t->ram2_sel = 0; t->ram2_we = 0;
	t->p1p2 = 0xFFFF; t->dsw = 0xF7FF;           // MAME's DSW default (.mra: FF,F7)
	for (int i = 0; i < 64; i++) tick();
	for (int i = 0; i < 0x3C000; i++) { t->dl_we = 1; t->dl_addr = i; t->dl_data = img[i]; tick(); }
	t->dl_we = 0;
	for (int i = 0; i < 64; i++) tick();
	t->reset = 0;
	int frame = 0, bestoff = 9999; long exact = 0, compared = 0;
	unsigned last_irq = 0;
	int prev_vs = 0;
	while (frame < frames) {
		tick();
		// frame boundary: the start of vblank (MAME's frame_done)
		int vs = t->vcount == 240;
		if (vs && !prev_vs) {
			frame++; cur_frame = frame;
			if (play) {
				int F = frame;               // gn_play.lua's F: frame_done count
				uint16_t in = 0xFFFF;
				if (F >= F0 && F < F0 + 6) in &= ~(1 << 12);          // coin 1
				if (F >= F0 + 60 && F < F0 + 66) in &= ~(1 << 14);    // start 1
				if (F >= F0 + 120) {
					if ((F % 8) < 4) in &= ~(1 << 4);                  // button 1
					if ((F % 97) < 6) in &= ~(1 << 5);                 // button 2
					static const int mv[7][2] = {{-1,-1},{3,-1},{3,-1},{2,-1},{3,0},{1,-1},{3,-1}};
					const int *m = mv[(F / 60) % 7];
					for (int k = 0; k < 2; k++) if (m[k] >= 0) in &= ~(1 << m[k]);
					// the lives poke: pause, write 0x020058 = 3, resume
					t->pause = 1; for (int i = 0; i < 16; i++) tick();
					t->ram2_sel = 1; t->ram2_addr = 0x2C; t->ram2_be = 3; t->ram2_din = 3; t->ram2_we = 1; tick();
					t->ram2_we = 0; tick(); t->ram2_sel = 0; t->pause = 0;
				}
				t->p1p2 = in;
			}
			// the picture of the frame that just ended
			if (fdir) { char fn[512]; snprintf(fn, sizeof fn, "%s/f%05d.raw", fdir, frame); FILE *f = fopen(fn, "wb"); fwrite(fb.data(), 4, fb.size(), f); fclose(f); }
			if (trace && frame > 40) {
				auto cmp = [&](int F) -> int {
					char fn[512]; snprintf(fn, sizeof fn, "%s/p%05d.raw", trace, F);
					FILE *f = fopen(fn, "rb"); if (!f) return -1;
					std::vector<uint32_t> p(256 * 224); size_t n = fread(p.data(), 4, p.size(), f); fclose(f);
					if (n != p.size()) return -1;
					int dd = 0; for (int i = 0; i < 256 * 224; i++) dd += (fb[i] & 0xFFFFFF) != (p[i] & 0xFFFFFF);
					return dd;
				};
				// every offset at which this frame is exact; a frame that matches at
				// exactly one offset pins the alignment (static frames match many)
				int nz = 0, only = 9999, dcur = -1;
				for (int o = -8; o <= 8; o++) { int dd = cmp(frame + o); if (dd == 0) { nz++; only = o; } if (o == bestoff) dcur = dd; }
				if (nz == 1 && only != bestoff) { if (bestoff != 9999) printf("  frame %d: alignment moves %+d -> %+d\n", frame, bestoff, only); bestoff = only; dcur = 0; }
				if (bestoff != 9999) { compared++; if (dcur == 0) exact++;
					else if (getenv("MP_SHOWDIFF")) printf("  frame %d vs MAME %d: %d differ (exact at %d offsets)\n", frame, frame + bestoff, dcur, nz); }
			}
			if (frame % EVERY == 0) {
				int nb = 0; for (auto p : fb) nb += (p & 0xFFFFFF) != 0;
				printf("f=%d nonblack=%d irq1=%u(+%u) iack1=%u pc=%06x spr_over=%u | MAME offset %+d, exact %ld/%ld\n",
				       frame, nb, t->dbg_irq1, t->dbg_irq1 - last_irq, t->dbg_iack1, t->dbg_addr, t->dbg_spr_overruns,
				       bestoff == 9999 ? 0 : bestoff, exact, compared);
				fflush(stdout); last_irq = t->dbg_irq1;
			}
		}
		prev_vs = vs;
	}
	printf("done: %d frames; against MAME: %ld of %ld exact (offset %+d)\n", frame, exact, compared, bestoff == 9999 ? 0 : bestoff);
	if (wav) fclose(wav);
	delete t;
	return 0;
}
