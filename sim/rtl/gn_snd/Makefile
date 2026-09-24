# The sound board alone against MAME's bus trace (docs/PLAN.md M0, Q1/Q2):
#   make && ./obj_dir/Vgn_sound SND_BIN MAME_TRACE OUT_TRACE MS
# The rule depends on every RTL file Verilator pulls in through -y (MS1-58).
RTL := ../../../rtl
SRCS := $(wildcard $(RTL)/gingan/*.sv) $(RTL)/third_party/mc6809/mc6809is.v
all: obj_dir/Vgn_sound
obj_dir/Vgn_sound: tb.cpp $(SRCS)
	verilator --cc --exe --build -O3 -j 8 -CFLAGS -O3 --x-assign fast --x-initial fast -Wno-fatal \
		-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD \
		--top-module gn_sound -y $(RTL)/gingan $(RTL)/third_party/mc6809/mc6809is.v $(RTL)/gingan/gn_sound.sv tb.cpp -o Vgn_sound
lint:
	verilator --lint-only -Wall -Wno-fatal --top-module gn_sound -y $(RTL)/gingan \
		$(RTL)/third_party/mc6809/mc6809is.v $(RTL)/gingan/gn_sound.sv 2>&1 \
		| grep -A1 -E '^%(Error|Warning-(UNDRIVEN|IMPLICIT|USEDBEFOREDECL))' | grep -B1 'rtl/gingan/' ; test $$? -ne 0
clean:
	rm -rf obj_dir
.PHONY: all lint clean
