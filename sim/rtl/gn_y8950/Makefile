# The Y8950 against MAME's ymfm (sim/oracle/ymfm_y8950), on a sound trace:
#   make && ./obj_dir/Vgn_y8950 TRACE ADPCM_ROM OUT_PREFIX MS MODE   (MODE all | fm | adpcm)
# The rule depends on every RTL file Verilator pulls in through -y (MS1-58).
RTL := ../../../rtl
SRCS := $(wildcard $(RTL)/gingan/*.sv) $(wildcard $(RTL)/third_party/jtopl/*.v)
all: obj_dir/Vgn_y8950
obj_dir/Vgn_y8950: tb.cpp $(SRCS)
	verilator --cc --exe --build -O3 -j 8 -CFLAGS -O3 --x-assign fast --x-initial fast -Wno-fatal \
		-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-LATCH \
		--top-module gn_y8950 -y $(RTL)/gingan -y $(RTL)/third_party/jtopl $(RTL)/gingan/gn_y8950.sv tb.cpp -o Vgn_y8950
clean:
	rm -rf obj_dir
.PHONY: all clean
