# Makefile for Für Elise FM Transmitter
# Supports simulation with Icarus Verilog and synthesis with Yosys
#
# Usage:
#   make sim      - Run simulation
#   make wave     - View waveforms (requires gtkwave)
#   make synth    - Synthesize design
#   make clean    - Remove generated files

#-----------------------------------------------------------------------------
# Project Configuration
#-----------------------------------------------------------------------------
PROJECT = fur_elise_fm
TOP_MODULE = fur_elise_fm_top

# Directories
RTL_DIR = rtl
TB_DIR = tb
BUILD_DIR = build

# Source files
RTL_SOURCES = $(RTL_DIR)/fur_elise_fm_top.v \
              $(RTL_DIR)/melody_rom.v \
              $(RTL_DIR)/melody_sequencer.v \
              $(RTL_DIR)/fm_modulator.v

TB_SOURCES = $(TB_DIR)/fur_elise_fm_tb.v

#-----------------------------------------------------------------------------
# Tools
#-----------------------------------------------------------------------------
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave
YOSYS = yosys

#-----------------------------------------------------------------------------
# Build Outputs
#-----------------------------------------------------------------------------
SIM_OUT = $(BUILD_DIR)/$(PROJECT)_tb
VCD_FILE = $(PROJECT)_tb.vcd
SYNTH_OUT = $(BUILD_DIR)/$(PROJECT)_synth.v

#-----------------------------------------------------------------------------
# Targets
#-----------------------------------------------------------------------------
.PHONY: all sim wave synth clean help

all: sim

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

#-----------------------------------------------------------------------------
# Simulation
#-----------------------------------------------------------------------------
sim: $(BUILD_DIR) $(SIM_OUT)
	@echo "Running simulation..."
	cd $(BUILD_DIR) && $(VVP) $(PROJECT)_tb
	@mv $(VCD_FILE) $(BUILD_DIR)/ 2>/dev/null || true
	@echo "Simulation complete. VCD file: $(BUILD_DIR)/$(VCD_FILE)"

$(SIM_OUT): $(RTL_SOURCES) $(TB_SOURCES)
	@echo "Compiling testbench..."
	$(IVERILOG) -o $(SIM_OUT) -I$(RTL_DIR) $(TB_SOURCES) $(RTL_SOURCES)

#-----------------------------------------------------------------------------
# Waveform Viewing
#-----------------------------------------------------------------------------
wave: $(BUILD_DIR)/$(VCD_FILE)
	$(GTKWAVE) $(BUILD_DIR)/$(VCD_FILE) &

$(BUILD_DIR)/$(VCD_FILE): sim

#-----------------------------------------------------------------------------
# Synthesis (generic, no target technology)
#-----------------------------------------------------------------------------
synth: $(BUILD_DIR) $(SYNTH_OUT)
	@echo "Synthesis complete: $(SYNTH_OUT)"

$(SYNTH_OUT): $(RTL_SOURCES)
	@echo "Synthesizing design..."
	$(YOSYS) -p "read_verilog $(RTL_SOURCES); \
	             synth -top $(TOP_MODULE); \
	             opt; \
	             write_verilog $(SYNTH_OUT)"

#-----------------------------------------------------------------------------
# Synthesis for GF180MCU (requires PDK)
#-----------------------------------------------------------------------------
synth-gf180: $(BUILD_DIR)
	@echo "Synthesizing for GF180MCU..."
	@echo "Note: Requires GF180MCU PDK and OpenLane installation"
	@echo "This target is a placeholder - adjust paths for your setup"
	# Example command (adjust paths):
	# $(YOSYS) -p "read_verilog $(RTL_SOURCES); \
	#              synth -top $(TOP_MODULE); \
	#              dfflibmap -liberty /path/to/gf180mcu.lib; \
	#              abc -liberty /path/to/gf180mcu.lib; \
	#              write_verilog $(BUILD_DIR)/$(PROJECT)_gf180.v"

#-----------------------------------------------------------------------------
# Lint Check
#-----------------------------------------------------------------------------
lint: $(RTL_SOURCES)
	@echo "Running lint check..."
	$(IVERILOG) -Wall -Wno-timescale -o /dev/null $(RTL_SOURCES)
	@echo "Lint check passed"

#-----------------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vcd

#-----------------------------------------------------------------------------
# Help
#-----------------------------------------------------------------------------
help:
	@echo "Für Elise FM Transmitter - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  sim          Run simulation with Icarus Verilog"
	@echo "  wave         View waveforms with GTKWave"
	@echo "  synth        Generic synthesis with Yosys"
	@echo "  synth-gf180  Synthesis for GF180MCU (requires PDK)"
	@echo "  lint         Run lint check"
	@echo "  clean        Remove generated files"
	@echo "  help         Show this help"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Icarus Verilog (iverilog, vvp)"
	@echo "  - GTKWave (for waveform viewing)"
	@echo "  - Yosys (for synthesis)"
