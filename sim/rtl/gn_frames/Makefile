# M2: the whole board from reset (fx68k, mc6809is, both chips), ROMs as arrays:
#   make && ./obj_dir/Vgn_core IMAGE_DIR FRAMES
# The rule depends on every RTL file Verilator pulls in through -y (MS1-58).
RTL := ../../../rtl
TP  := $(RTL)/third_party
SRCS := $(wildcard $(RTL)/gingan/*.sv) $(wildcard $(TP)/jtopl/*.v) $(TP)/ym2149/ym2149_zx.sv $(TP)/mc6809/mc6809is.v \
        $(TP)/fx68k/fx68k.sv $(TP)/fx68k/fx68kAlu.sv $(TP)/fx68k/uaddrPla.sv
VFLAGS := -Wno-fatal -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-LATCH \
          -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-COMBDLY -Wno-CASEOVERLAP -Wno-IMPLICIT -Wno-SELRANGE -Wno-UNSIGNED
INCS := -y $(RTL)/gingan -y $(TP)/jtopl $(TP)/ym2149/ym2149_zx.sv $(TP)/mc6809/mc6809is.v \
        $(TP)/fx68k/fx68k.sv $(TP)/fx68k/fx68kAlu.sv $(TP)/fx68k/uaddrPla.sv
all: obj_dir/Vgn_core microrom.mem nanorom.mem
microrom.mem nanorom.mem:
	cp $(TP)/fx68k/$@ .
obj_dir/Vgn_core: tb.cpp $(SRCS)
	verilator --cc --exe --build -O3 -j 8 -CFLAGS -O3 --x-assign fast --x-initial fast $(VFLAGS) \
		--top-module gn_core $(INCS) $(RTL)/gingan/gn_core.sv tb.cpp -o Vgn_core
# fails on undriven, implicit and used-before-declared signals in rtl/gingan (NMKBP964's lesson)
lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-BLKANDNBLK --top-module gn_core $(INCS) $(RTL)/gingan/gn_core.sv 2>&1 \
		| grep -A1 -E '^%(Error|Warning-(UNDRIVEN|IMPLICIT|USEDBEFOREDECL))' | grep -B1 'rtl/gingan/' ; test $$? -ne 0
clean:
	rm -rf obj_dir
.PHONY: all lint clean
