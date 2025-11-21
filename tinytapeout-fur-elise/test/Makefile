# TinyTapeout Fur Elise FM Testbench Makefile

IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

SRC_DIR = ../src
TB = tb.v
SRC_FILES = $(wildcard $(SRC_DIR)/*.v)

all: sim

sim: tb
	$(VVP) tb

tb: $(TB) $(SRC_FILES)
	$(IVERILOG) -o tb $(TB) $(SRC_FILES)

wave: sim
	$(GTKWAVE) tb.vcd &

clean:
	rm -f tb tb.vcd

.PHONY: all sim wave clean
