// The Y8950 oracle: MAME's ymfm y8950 (~/mame/3rdparty/ymfm, compiled in
// place, reference only) driven by the register writes of a sound trace
// (sim/oracle/gn_sndtrace.lua, "opl" lines), one output sample per
// clock/72 (49,716 Hz at 3.579545 MHz), as MAME runs it.
//
//   ymfm_y8950 TRACE ADPCM_ROM OUT_PREFIX [MS] [MODES]
//
// Writes OUT_PREFIX.all / .fm / .adpcm: little-endian int16 streams of the
// whole chip, of the chip with every ADPCM-register write dropped, and with
// every FM write dropped (0x07-0x12, 0x15-0x17 and 0x08 are ADPCM; 0x04 goes
// to both, as y8950::write_data routes it), plus .mel (FM with rhythm mode
// never enabled: 0xBD dropped) and .rhy (FM with no key-on on channels 0-5:
// 0xB0-0xB5 dropped). MODES (default "all,fm,adpcm") picks which to write.
// Each write lands before the
// first sample whose time is at or after it.
#include "ymfm_opl.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
struct Intf : ymfm::ymfm_interface {
	std::vector<uint8_t> rom;
	uint8_t ymfm_external_read(ymfm::access_class type, uint32_t address) override {
		return (type == ymfm::ACCESS_ADPCM_B && address < rom.size()) ? rom[address] : 0;
	}
};
static bool is_adpcm(int r) { return (r >= 0x07 && r <= 0x12) || (r >= 0x15 && r <= 0x17); }
static bool keep_write(const char *mode, int reg) {
	bool ad = is_adpcm(reg);
	if (!strcmp(mode, "all")) return true;
	if (reg == 0x04) return true;
	if (!strcmp(mode, "adpcm")) return ad;
	if (ad) return false;
	if (!strcmp(mode, "mel")) return reg != 0xBD;
	if (!strcmp(mode, "rhy")) return !(reg >= 0xB0 && reg <= 0xB5);
	return true;                                                   // fm
}
int main(int argc, char **argv) {
	if (argc < 4) { fprintf(stderr, "usage: TRACE ADPCM_ROM OUT_PREFIX [MS]\n"); return 1; }
	double end_ms = argc > 4 ? atof(argv[4]) : 1e12;
	struct W { double t; int a0; int d; };
	std::vector<W> w;
	FILE *f = fopen(argv[1], "r"); char line[256];
	while (fgets(line, sizeof line, f)) {
		double t; char dev[16], rw[4]; unsigned off, d;
		if (sscanf(line, "%lf %15s %3s %x %x", &t, dev, rw, &off, &d) == 5 && !strcmp(dev, "opl") && rw[0] == 'W') w.push_back({t, (int)off, (int)d});
	}
	fclose(f);
	const double rate = 3579545.0 / 72.0;
	std::vector<std::string> modes;
	{ std::string m = argc > 5 ? argv[5] : "all,fm,adpcm"; size_t p0 = 0;
	  while (p0 <= m.size()) { size_t q = m.find(',', p0); if (q == std::string::npos) q = m.size(); modes.push_back(m.substr(p0, q - p0)); p0 = q + 1; } }
	for (auto &mode : modes) {
		Intf intf;
		FILE *r = fopen(argv[2], "rb"); intf.rom.resize(0x20000); fread(intf.rom.data(), 1, 0x20000, r); fclose(r);
		ymfm::y8950 chip(intf);
		chip.reset();
		char fn[512]; snprintf(fn, sizeof fn, "%s.%s", argv[3], mode.c_str());
		FILE *out = fopen(fn, "wb");
		size_t wi = 0; int reg = 0;
		uint64_t n_end = (uint64_t)(end_ms * 1e-3 * rate);
		for (uint64_t n = 0; n < n_end && (wi < w.size() || n < n_end); n++) {
			double tn = n / rate * 1e9;
			while (wi < w.size() && w[wi].t <= tn) {
				if (w[wi].a0 == 0) { reg = w[wi].d; chip.write(0, w[wi].d); }
				else if (keep_write(mode.c_str(), reg)) chip.write(1, w[wi].d);
				wi++;
			}
			if (wi >= w.size() && end_ms > 1e11) break;
			ymfm::y8950::output_data o;
			chip.generate(&o, 1);
			int16_t s = (int16_t)o.data[0];
			fwrite(&s, 2, 1, out);
		}
		fclose(out);
		printf("%s: %zu writes\n", fn, wi);
	}
	return 0;
}
