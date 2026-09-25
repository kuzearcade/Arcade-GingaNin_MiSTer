# M3: the core on the real memory path (gn_rom_hw + rtl/sdram.sv + the SDRAM model):
#   make && ./obj_dir/Vhw_top IMAGE_DIR FRAMES
RTL := ../../../rtl
TP  := $(RTL)/third_party
SRCS := $(wildcard $(RTL)/gingan/*.sv) $(RTL)/sdram.sv $(RTL)/sdram_arb.sv $(RTL)/sdram_req.sv ../../models/sdram_model.sv \
        $(wildcard $(TP)/jtopl/*.v) $(TP)/ym2149/ym2149_zx.sv $(TP)/mc6809/mc6809is.v \
        $(TP)/fx68k/fx68k.sv $(TP)/fx68k/fx68kAlu.sv $(TP)/fx68k/uaddrPla.sv
VFLAGS := -Wno-fatal -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-LATCH \
          -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-COMBDLY -Wno-CASEOVERLAP -Wno-IMPLICIT -Wno-SELRANGE -Wno-UNSIGNED
INCS := -y $(RTL)/gingan -y $(RTL) -y ../../models -y $(TP)/jtopl $(TP)/ym2149/ym2149_zx.sv $(TP)/mc6809/mc6809is.v \
        $(TP)/fx68k/fx68k.sv $(TP)/fx68k/fx68kAlu.sv $(TP)/fx68k/uaddrPla.sv
all: obj_dir/Vhw_top microrom.mem nanorom.mem
microrom.mem nanorom.mem:
	cp $(TP)/fx68k/$@ .
obj_dir/Vhw_top: tb.cpp hw_top.sv $(SRCS)
	verilator --cc --exe --build -O3 -j 8 -CFLAGS -O3 --x-assign fast --x-initial fast +define+SIMULATION $(VFLAGS) \
		--top-module hw_top $(INCS) hw_top.sv tb.cpp -o Vhw_top
clean:
	rm -rf obj_dir
.PHONY: all clean
