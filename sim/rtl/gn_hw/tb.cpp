// M3: the core on its real memory path (docs/PLAN.md M3).
//   ./obj_dir/Vhw_top IMAGE_DIR FRAMES
// IMAGE_DIR is ~/gn_images/<set>/ (image.bin is the .mra's byte stream).
// The testbench plays Main_MiSTer: it sends image.bin through the ioctl
// interface, honouring ioctl_wait. Then:
//   - the copy check: the SDRAM model holds the image word for word;
//   - the response check: every acknowledged ROM read on the four streams is
//     compared with the image at the address the engine is holding;
//   - latency: clocks from a request's rise to its ack, per stream;
//   - frames: MP_REFDIR=dir compares every picture with M2's fNNNNN.raw
//     (sim/rtl/gn_frames with MP_FRAMEDIR): the memory path must not change one
//     pixel. MP_FRAMEDIR writes this run's frames.
//   MP_PLAY=1 as gn_frames; MP_EVERY=n status lines.
#include "Vhw_top.h"
#include "Vhw_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
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
	const char *refdir = getenv("MP_REFDIR"), *fdir = getenv("MP_FRAMEDIR");
	bool play = getenv("MP_PLAY") != nullptr;
	int EVERY = env("MP_EVERY", 60), F0 = 600;
	Vhw_top *t = new Vhw_top;
	std::vector<uint32_t> fb(256 * 224);
	int ph = -1, pv = -1;
	// the response check and latency, sampled on each clk_sys rise
	struct Stream { const char *name; uint32_t base; long n = 0, bad = 0, lat_sum = 0, lat_max = 0, lat = 0; bool req_d = false; };
	Stream st[4] = {{"BG", 0x3C000}, {"FG", 0x5C000}, {"SPR", 0x7C000}, {"ADPCM", 0xCC000}};
	auto row = [&](uint32_t a) { uint32_t v = 0; for (int i = 0; i < 4; i++) v = v << 8 | (a + i < img.size() ? img[a + i] : 0); return v; };
	auto check = [&]() {
		bool req[4] = {(bool)t->t_bg_req, (bool)t->t_fg_req, (bool)t->t_spr_req, (bool)t->t_adp_req};
		bool ack[4] = {(bool)t->t_bg_ack, (bool)t->t_fg_ack, (bool)t->t_spr_ack, (bool)t->t_adp_ack};
		uint32_t addr[4] = {t->t_bg_addr, t->t_fg_addr, t->t_spr_addr, t->t_adp_addr};
		for (int k = 0; k < 4; k++) {
			Stream &s = st[k];
			if (req[k] && !s.req_d) s.lat = 0;
			if (req[k]) s.lat++;
			if (ack[k]) {
				s.n++; s.lat_sum += s.lat; if (s.lat > s.lat_max) s.lat_max = s.lat;
				uint32_t want = k < 3 ? row(s.base + addr[k]) : img[s.base + addr[k]];
				uint32_t got = k == 0 ? t->t_bg_data : k == 1 ? t->t_fg_data : k == 2 ? t->t_spr_data : t->t_adp_data;
				if (got != want && s.bad++ < 5) printf("%s mismatch #%ld: addr %06x got %08x want %08x\n", s.name, s.n, addr[k], got, want);
			}
			s.req_d = req[k];
		}
	};
	// clk_ram = 2 x clk_sys: clk_sys rises with every other clk_ram rise
	uint64_t cyc = 0;
	auto tick = [&]() {
		for (int p = 0; p < 2; p++) {
			t->clk_ram = 0; t->eval();
			t->clk_ram = 1; t->clk_sys = p == 0; t->eval();
		}
		cyc++;
		check();
		if (t->ce_pix) {
			if (ph >= 0 && ph < 256 && pv >= 16 && pv < 240) fb[(pv - 16) * 256 + ph] = t->rgb;
			ph = t->hcount; pv = t->vcount;
		}
	};
	t->pwr_reset = 1; t->reset = 1; t->pause = 0; t->ioctl_download = 0; t->ioctl_wr = 0;
	t->ram2_sel = 0; t->ram2_we = 0; t->p1p2 = 0xFFFF; t->dsw = 0xF7FF;
	for (int i = 0; i < 200; i++) tick();
	t->pwr_reset = 0;
	while (!t->sdram_ready) tick();
	for (int i = 0; i < 100; i++) tick();
	// the download
	uint64_t dl0 = cyc;
	t->ioctl_download = 1; tick();
	for (size_t i = 0; i < img.size(); i++) {
		t->ioctl_addr = i; t->ioctl_dout = img[i]; t->ioctl_wr = 1; tick(); t->ioctl_wr = 0;
		tick(); while (t->ioctl_wait) tick();
	}
	for (int i = 0; i < 100; i++) tick();
	t->ioctl_download = 0;
	printf("download: %zu bytes, %u accepted, %.1f ms at 48 MHz\n", img.size(), t->dbg_dl_bytes, (cyc - dl0) / 48000.0);
	// the copy check
	{
		auto &mem = t->rootp->hw_top__DOT__u_model__DOT__mem;
		long bad = 0;
		for (size_t k = 0; k < img.size() / 2; k++) {
			uint16_t want = img[2 * k] | img[2 * k + 1] << 8;
			if (mem[k] != want && bad++ < 5) printf("copy mismatch at byte %06zx: %04x want %04x\n", 2 * k, mem[k], want);
		}
		printf("copy check: %ld of %zu words differ\n", bad, img.size() / 2);
	}
	for (int i = 0; i < 64; i++) tick();
	t->reset = 0;
	int frame = 0, prev_vs = 0; long same = 0, compared = 0;
	while (frame < frames) {
		tick();
		int vs = t->vcount == 240;
		if (vs && !prev_vs) {
			frame++;
			if (play) {
				int F = frame; uint16_t in = 0xFFFF;
				if (F >= F0 && F < F0 + 6) in &= ~(1 << 12);
				if (F >= F0 + 60 && F < F0 + 66) in &= ~(1 << 14);
				if (F >= F0 + 120) {
					if ((F % 8) < 4) in &= ~(1 << 4);
					if ((F % 97) < 6) in &= ~(1 << 5);
					static const int mv[7][2] = {{-1,-1},{3,-1},{3,-1},{2,-1},{3,0},{1,-1},{3,-1}};
					const int *m = mv[(F / 60) % 7];
					for (int k = 0; k < 2; k++) if (m[k] >= 0) in &= ~(1 << m[k]);
					t->pause = 1; for (int i = 0; i < 16; i++) tick();
					t->ram2_sel = 1; t->ram2_addr = 0x2C; t->ram2_be = 3; t->ram2_din = 3; t->ram2_we = 1; tick();
					t->ram2_we = 0; tick(); t->ram2_sel = 0; t->pause = 0;
				}
				t->p1p2 = in;
			}
			if (fdir) { char fn[512]; snprintf(fn, sizeof fn, "%s/f%05d.raw", fdir, frame); FILE *f = fopen(fn, "wb"); fwrite(fb.data(), 4, fb.size(), f); fclose(f); }
			if (refdir) {
				char fn[512]; snprintf(fn, sizeof fn, "%s/f%05d.raw", refdir, frame);
				FILE *f = fopen(fn, "rb");
				if (f) {
					std::vector<uint32_t> p(256 * 224); size_t n = fread(p.data(), 4, p.size(), f); fclose(f);
					if (n == p.size()) {
						int dd = 0; for (int i = 0; i < 256 * 224; i++) dd += (fb[i] & 0xFFFFFF) != (p[i] & 0xFFFFFF);
						compared++; if (!dd) same++; else printf("  frame %d: %d pixels differ from M2\n", frame, dd);
					}
				}
			}
			if (frame % EVERY == 0) {
				printf("f=%d irq1=%u spr_over=%u dropped=%04x | same as M2 %ld/%ld |", frame, t->dbg_irq1, t->dbg_spr_overruns, t->dbg_dropped, same, compared);
				for (auto &s : st) printf(" %s %ld bad %ld lat avg %.1f max %ld;", s.name, s.n, s.bad, s.n ? (double)s.lat_sum / s.n : 0.0, s.lat_max);
				printf("\n"); fflush(stdout);
			}
		}
		prev_vs = vs;
	}
	printf("done: %d frames; same as M2 %ld of %ld; overruns %u; dropped %04x\n", frame, same, compared, t->dbg_spr_overruns, t->dbg_dropped);
	for (auto &s : st) printf("  %-5s %8ld reads, %ld bad, latency avg %.1f max %ld clk_sys\n", s.name, s.n, s.bad, s.n ? (double)s.lat_sum / s.n : 0.0, s.lat_max);
	delete t;
	return 0;
}
