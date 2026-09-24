# M1: the video block from a MAME state against MAME's picture (GN-2 pairing):
#   make && ./obj_dir/Vgn_video SET TRACE_DIR F [F ...]
# The rule depends on every RTL file Verilator pulls in through -y (MS1-58).
RTL := ../../../rtl
SRCS := $(wildcard $(RTL)/gingan/*.sv)
all: obj_dir/Vgn_video
obj_dir/Vgn_video: tb.cpp $(SRCS)
	verilator --cc --exe --build -O3 -j 8 -CFLAGS -O3 --x-assign fast --x-initial fast -Wno-fatal \
		-Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		--top-module gn_video -y $(RTL)/gingan $(RTL)/gingan/gn_video.sv tb.cpp -o Vgn_video
clean:
	rm -rf obj_dir
.PHONY: all clean
