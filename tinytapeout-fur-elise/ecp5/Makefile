# ECP5 Makefile for Fur Elise FM Transmitter
# Target: Vahya Mini ECP5 board
# Tested with OSS CAD Suite
# Reference: https://github.com/r4d10n/vahya

PROJECT = fur_elise_fm_ecp5
TOP_MODULE = tt_um_fur_elise_fm
DEVICE = 25k
PACKAGE = CABGA381
SPEED = 6

# Source files
SRC_DIR = ../src
VERILOG_SRC = \
	$(SRC_DIR)/project.v \
	$(SRC_DIR)/fur_elise_fm_top.v \
	$(SRC_DIR)/melody_rom.v \
	$(SRC_DIR)/melody_sequencer.v \
	$(SRC_DIR)/fm_modulator.v \
	$(SRC_DIR)/audio_tone_generator.v \
	$(SRC_DIR)/clock_doubler.v \
	$(SRC_DIR)/pwm_input_decoder.v

# Constraint files
LPF = $(PROJECT).lpf

# Output files
JSON = $(PROJECT).json
TEXTCFG = $(PROJECT)_out.config
BIT = $(PROJECT).bit
SVF = $(PROJECT).svf

# Tools
YOSYS = yosys
NEXTPNR = nextpnr-ecp5
ECPPACK = ecppack
OPENOCD = openocd

# Synthesis options
YOSYS_OPTS = -q -p "synth_ecp5 -top $(TOP_MODULE) -json $(JSON)"

# Place and route options
NEXTPNR_OPTS = \
	--$(DEVICE) \
	--package $(PACKAGE) \
	--speed $(SPEED) \
	--json $(JSON) \
	--textcfg $(TEXTCFG) \
	--lpf $(LPF) \
	--freq 50

# Targets
.PHONY: all synth pnr bit svf prog clean stats timing

all: bit

synth: $(JSON)

pnr: $(TEXTCFG)

bit: $(BIT)

svf: $(SVF)

$(JSON): $(VERILOG_SRC)
	@echo "==> Synthesis with Yosys"
	$(YOSYS) $(YOSYS_OPTS) $(VERILOG_SRC)
	@echo

$(TEXTCFG): $(JSON) $(LPF)
	@echo "==> Place and Route with nextpnr-ecp5"
	$(NEXTPNR) $(NEXTPNR_OPTS)
	@echo

$(BIT): $(TEXTCFG)
	@echo "==> Packing bitstream with ecppack"
	$(ECPPACK) --compress --freq 38.8 $(TEXTCFG) $(BIT)
	@echo

$(SVF): $(BIT)
	@echo "==> Generating SVF file"
	$(ECPPACK) --svf $(SVF) $(TEXTCFG) $(BIT)
	@echo

# Programming (adjust for your programmer)
prog: $(BIT)
	@echo "==> Programming ECP5"
	$(OPENOCD) -f ecp5-evn.cfg -c "transport select jtag; init; svf $(SVF); exit"

# Statistics
stats: $(JSON)
	@echo "==> Design Statistics"
	@grep -A 20 "=== $(TOP_MODULE) ===" yosys.log || true
	@echo
	@echo "Cell usage:"
	@$(YOSYS) -p "read_json $(JSON); stat" 2>&1 | grep -A 30 "Number of cells"

# Timing report
timing: $(TEXTCFG)
	@echo "==> Timing Report"
	$(NEXTPNR) --$(DEVICE) --json $(JSON) --textcfg $(TEXTCFG) --report timing_report.txt --timing-allow-fail
	@cat timing_report.txt | head -50

# Clean build artifacts
clean:
	rm -f $(JSON) $(TEXTCFG) $(BIT) $(SVF)
	rm -f yosys.log timing_report.txt
	rm -f *.rpt

help:
	@echo "ECP5 Fur Elise FM Transmitter Build System"
	@echo "Target: Vahya Mini ECP5 board"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build bitstream (default)"
	@echo "  synth    - Synthesis only"
	@echo "  pnr      - Place and route"
	@echo "  bit      - Generate bitstream"
	@echo "  svf      - Generate SVF for programming"
	@echo "  prog     - Program FPGA"
	@echo "  stats    - Show design statistics"
	@echo "  timing   - Show timing report"
	@echo "  clean    - Remove build artifacts"
	@echo ""
	@echo "Configuration:"
	@echo "  DEVICE  = $(DEVICE)"
	@echo "  PACKAGE = $(PACKAGE)"
	@echo "  SPEED   = $(SPEED)"
	@echo "  CLOCK   = 26 MHz (Vahya Mini)"
