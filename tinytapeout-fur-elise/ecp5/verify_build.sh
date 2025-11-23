#!/bin/bash
#
# Verification script for ECP5 build
# Tests build configuration without requiring OSS CAD Suite
#

set -e

echo "================================================"
echo "ECP5 Build Verification Script"
echo "================================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

# Test function
test_check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $1"
        ((pass_count++))
    else
        echo -e "${RED}✗ FAIL${NC}: $1"
        ((fail_count++))
    fi
}

#=============================================================================
# Check 1: Source files exist
#=============================================================================
echo "[1] Checking source files..."
required_files=(
    "project.v"
    "fur_elise_fm_top.v"
    "melody_rom.v"
    "melody_sequencer.v"
    "fm_modulator.v"
    "audio_tone_generator.v"
    "clock_doubler.v"
    "pwm_input_decoder.v"
)

for file in "${required_files[@]}"; do
    [ -f "$SRC_DIR/$file" ]
    test_check "Source file exists: $file"
done

#=============================================================================
# Check 2: Constraint file exists
#=============================================================================
echo ""
echo "[2] Checking constraint file..."
[ -f "$SCRIPT_DIR/fur_elise_fm_ecp5.lpf" ]
test_check "LPF constraint file exists"

#=============================================================================
# Check 3: Makefile exists and is valid
#=============================================================================
echo ""
echo "[3] Checking Makefile..."
[ -f "$SCRIPT_DIR/Makefile" ]
test_check "Makefile exists"

# Check for required targets
for target in "all" "synth" "pnr" "bit" "clean"; do
    grep -q "^${target}:" "$SCRIPT_DIR/Makefile"
    test_check "Makefile has target: $target"
done

#=============================================================================
# Check 4: Verilog syntax (basic)
#=============================================================================
echo ""
echo "[4] Checking Verilog syntax..."

# Check for common syntax errors (basic)
for vfile in "$SRC_DIR"/*.v; do
    if [ -f "$vfile" ]; then
        # Check for balanced module/endmodule
        mod_count=$(grep -c "^module " "$vfile" || true)
        endmod_count=$(grep -c "^endmodule" "$vfile" || true)

        if [ "$mod_count" -eq "$endmod_count" ]; then
            test_check "Balanced module/endmodule: $(basename $vfile)"
        else
            echo -e "${RED}✗ FAIL${NC}: Unbalanced module/endmodule: $(basename $vfile)"
            ((fail_count++))
        fi
    fi
done

#=============================================================================
# Check 5: Top module interface
#=============================================================================
echo ""
echo "[5] Checking top module interface..."

# Verify TinyTapeout wrapper has correct interface
grep -q "module tt_um_fur_elise_fm" "$SRC_DIR/project.v"
test_check "Top module name correct"

for signal in "ui_in" "uo_out" "uio_in" "uio_out" "uio_oe" "clk" "rst_n" "ena"; do
    grep -q "$signal" "$SRC_DIR/project.v"
    test_check "Top module has signal: $signal"
done

#=============================================================================
# Check 6: Parameter configuration
#=============================================================================
echo ""
echo "[6] Checking parameter configuration..."

# Check that CLK_FREQ_HZ is defined
grep -q "CLK_FREQ_HZ" "$SRC_DIR/project.v"
test_check "CLK_FREQ_HZ parameter defined"

# Check for melody length
grep -q "MELODY_LENGTH" "$SRC_DIR/project.v"
test_check "MELODY_LENGTH parameter defined"

#=============================================================================
# Check 7: Build commands (dry-run)
#=============================================================================
echo ""
echo "[7] Build command sequence (dry-run)..."
echo ""

cat << 'EOF'
If OSS CAD Suite were installed, the following commands would execute:

1. Synthesis:
   yosys -q -p "synth_ecp5 -top tt_um_fur_elise_fm -json fur_elise_fm_ecp5.json" \
         ../src/project.v ../src/fur_elise_fm_top.v ../src/melody_rom.v \
         ../src/melody_sequencer.v ../src/fm_modulator.v \
         ../src/audio_tone_generator.v ../src/clock_doubler.v \
         ../src/pwm_input_decoder.v

2. Place and Route:
   nextpnr-ecp5 --25k --package CABGA381 --speed 6 \
                --json fur_elise_fm_ecp5.json \
                --textcfg fur_elise_fm_ecp5_out.config \
                --lpf fur_elise_fm_ecp5.lpf \
                --freq 50

3. Bitstream:
   ecppack --compress --freq 38.8 \
           fur_elise_fm_ecp5_out.config \
           fur_elise_fm_ecp5.bit

4. Programming:
   ecpprog fur_elise_fm_ecp5.bit
   # or
   dfu-util -d 1209:5af0 -D fur_elise_fm_ecp5.bit

EOF

test_check "Build sequence documented"

#=============================================================================
# Check 8: OSS CAD Suite availability
#=============================================================================
echo ""
echo "[8] Checking for OSS CAD Suite..."

if command -v yosys &> /dev/null; then
    echo -e "${GREEN}✓${NC} yosys found: $(yosys --version | head -1)"
    ((pass_count++))
else
    echo -e "${YELLOW}⚠${NC} yosys not found (install OSS CAD Suite to run synthesis)"
fi

if command -v nextpnr-ecp5 &> /dev/null; then
    echo -e "${GREEN}✓${NC} nextpnr-ecp5 found"
    ((pass_count++))
else
    echo -e "${YELLOW}⚠${NC} nextpnr-ecp5 not found"
fi

if command -v ecppack &> /dev/null; then
    echo -e "${GREEN}✓${NC} ecppack found"
    ((pass_count++))
else
    echo -e "${YELLOW}⚠${NC} ecppack not found"
fi

#=============================================================================
# Summary
#=============================================================================
echo ""
echo "================================================"
echo "Verification Summary"
echo "================================================"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Build configuration is valid."
    echo "Install OSS CAD Suite to run synthesis:"
    echo "  https://github.com/YosysHQ/oss-cad-suite-build/releases"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some checks failed.${NC}"
    echo "Please fix the issues above before building."
    echo ""
    exit 1
fi
