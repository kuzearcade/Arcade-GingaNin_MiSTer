// gn_y8950 on a sound trace's Y8950 writes (times from MAME), one output
// sample per strobe, for comparison with sim/oracle/ymfm_y8950. MODE drops
// the writes the oracle drops: fm = no ADPCM-register writes, adpcm = no FM
// writes (0x04 goes to both).
#include "Vgn_y8950.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
static bool is_adpcm(int r) { return (r >= 0x07 && r <= 0x12) || (r >= 0x15 && r <= 0x17); }
// the same filters as sim/oracle/ymfm_y8950 (all, fm, adpcm, mel, rhy)
static bool keep_write(const char *mode, int reg) {
	bool ad = is_adpcm(reg);
	if (!strcmp(mode, "all")) return true;
	if (reg == 0x04) return true;
	if (!strcmp(mode, "adpcm")) return ad;
	if (ad) return false;
	if (!strcmp(mode, "mel")) return reg != 0xBD;
	if (!strcmp(mode, "rhy")) return !(reg >= 0xB0 && reg <= 0xB5);
	return true;
}
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 6) { fprintf(stderr, "usage: TRACE ADPCM_ROM OUT MS MODE\n"); return 1; }
	struct W { double t; int a0, d; };
	std::vector<W> w;
	FILE *f = fopen(argv[1], "r"); char line[256];
	while (fgets(line, sizeof line, f)) {
		double t; char dev[16], rw[4]; unsigned off, d;
		if (sscanf(line, "%lf %15s %3s %x %x", &t, dev, rw, &off, &d) == 5 && !strcmp(dev, "opl") && rw[0] == 'W') w.push_back({t, (int)off, (int)d});
	}
	fclose(f);
	std::vector<uint8_t> rom(0x20000);
	f = fopen(argv[2], "rb"); if (fread(rom.data(), 1, rom.size(), f) != rom.size()) return 1; fclose(f);
	double end_ns = atof(argv[4]) * 1e6;
	const char *mode = argv[5];
	FILE *out = fopen(argv[3], "wb");
	Vgn_y8950 *t = new Vgn_y8950;
	uint64_t cyc = 0, acc = 0; size_t wi = 0; int reg = 0, memcnt = -1, nsamp = 0;
	t->reset = 1; t->wr = 0;
	auto tick = [&]() {
		t->clk = 0; t->eval();
		// ADPCM ROM: held request, ack with data after 8 clocks
		t->mem_ack = 0;
		if (t->mem_req) { if (memcnt < 0) memcnt = 8; else if (memcnt > 0 && --memcnt == 0) { t->mem_data = rom[t->mem_addr & 0x1FFFF]; t->mem_ack = 1; memcnt = -2; } }
		else memcnt = -1;
		t->clk = 1; t->eval(); cyc++;
		acc += 715909; t->cen = 0;
		if (acc >= 9600000) { acc -= 9600000; t->cen = 1; }
	};
	for (int i = 0; i < 2000; i++) tick();
	t->reset = 0;
	for (;;) {
		double ns = cyc * (1e9 / 48e6);
		if (ns > end_ns) break;
		t->wr = 0;
		if (wi < w.size() && ns >= w[wi].t) {
			bool keep = true;
			if (w[wi].a0 == 0) reg = w[wi].d;
			else keep = keep_write(mode, reg);
			if (keep) { t->wr = 1; t->a0 = w[wi].a0; t->din = w[wi].d; }
			wi++;
		}
		tick();
		if (t->sample) { int16_t s = t->snd; fwrite(&s, 2, 1, out); nsamp++; }
	}
	fclose(out);
	printf("%s: %d samples, %zu writes\n", argv[3], nsamp, wi);
	delete t;
	return 0;
}
