# ECP5 Build for Fur Elise FM Transmitter

This directory contains build files for synthesizing the Fur Elise FM transmitter
on ECP5 FPGAs using the open-source OSS CAD Suite.

## Prerequisites

### Install OSS CAD Suite

Download and install OSS CAD Suite from:
https://github.com/YosysHQ/oss-cad-suite-build/releases

```bash
# Download latest release
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-11-22/oss-cad-suite-linux-x64-20241122.tgz

# Extract
tar -xzf oss-cad-suite-linux-x64-20241122.tgz

# Add to PATH
export PATH="$PWD/oss-cad-suite/bin:$PATH"

# Verify installation
yosys --version
nextpnr-ecp5 --version
ecppack --version
```

## Supported Boards

- **ULX3S** (ECP5-25F/45F/85F)
- **OrangeCrab** (ECP5-25F/85F)
- **Versa ECP5** evaluation board
- Generic ECP5 boards

**Note:** Pin constraints in `fur_elise_fm_ecp5.lpf` are generic. Adjust for your specific board.

## Building

### Full Build (Synthesis + PnR + Bitstream)

```bash
make
```

This runs:
1. Synthesis with Yosys
2. Place and Route with nextpnr-ecp5
3. Bitstream generation with ecppack

### Synthesis Only

```bash
make synth
```

Generates `fur_elise_fm_ecp5.json` with synthesized netlist.

### Place and Route Only

```bash
make pnr
```

Requires `fur_elise_fm_ecp5.json` from synthesis step.

### View Statistics

```bash
make stats
```

Shows resource utilization:
- LUTs
- Flip-flops
- Block RAM
- DSP blocks

### Timing Report

```bash
make timing
```

Shows critical path timing analysis.

## Programming

### Generate SVF File

```bash
make svf
```

### Program via OpenOCD (JTAG)

```bash
make prog
```

**Note:** Adjust programmer settings in Makefile for your specific hardware.

### Program via ecpprog (ULX3S)

```bash
ecpprog fur_elise_fm_ecp5.bit
```

### Program via dfu-util (OrangeCrab)

```bash
dfu-util -d 1209:5af0 -D fur_elise_fm_ecp5.bit
```

## Pin Configuration

### Inputs

| Signal | Pin | Description |
|--------|-----|-------------|
| clk | G2 | 25 MHz clock input |
| rst_n | D6 | Reset button (active low) |
| ena | R1 | Enable (tie high or switch) |
| ui_in[0] | F1 | Enable playback |
| ui_in[1] | F2 | Loop melody |
| ui_in[2] | E1 | Clock doubling enable |
| ui_in[3] | E2 | PWM audio input |

### Outputs

| Signal | Pin | Description |
|--------|-----|-------------|
| uo_out[0] | B2 | FM output (antenna) |
| uo_out[1] | C3 | Audio output (speaker) |
| uo_out[2] | B1 | Playing status LED |
| uo_out[3] | H3 | Melody end LED |
| uo_out[7:4] | H4,J4,G3,G4 | Note index (debug) |

### Debug Outputs

| Signal | Pins | Description |
|--------|------|-------------|
| uio_out[7:0] | E3,D3,C4,B4,A2,A3,A4,A5 | Phase increment MSB |

## Expected Resource Usage

For ECP5-25K:

```
LUTs:         ~800-1000
Flip-flops:   ~250-300
Block RAM:    0
DSP blocks:   0
Max Freq:     > 100 MHz
```

## Clock Configuration

The design expects a 25 MHz input clock (typical for ECP5 dev boards).

Internal frequencies:
- System clock: 25 MHz
- FM carrier: ~6.25 MHz (12.5 MHz with clock doubling)
- Audio tones: 261-988 Hz (musical range)

To use a different input clock, modify the `CLK_FREQ_HZ` parameter in the top module:

```verilog
fur_elise_fm_top #(
    .CLK_FREQ_HZ(25_000_000),  // Change this
    ...
```

## Testing the Build

### Verify Synthesis

```bash
make synth 2>&1 | grep -A 20 "Number of cells"
```

Should show:
- TRELLIS_FF: ~250-300 (flip-flops)
- LUT4: ~800-1000 (logic)
- No critical warnings

### Verify Timing

```bash
make timing | grep -i "max frequency"
```

Should report > 50 MHz for comfortable operation.

## Hardware Connections

### FM Output

Connect `uo_out[0]` (fm_out) to:
- Antenna (10-30cm wire for testing)
- Spectrum analyzer for verification
- RF amplifier for increased range

**Warning:** Ensure compliance with local radio regulations!

### Audio Output

Connect `uo_out[1]` (audio_out) to:
- 8Ω speaker with 100Ω series resistor
- Audio amplifier input (3.3V logic level)
- Oscilloscope for waveform viewing

### Control Inputs

- `ui_in[0]` (enable): High to start playback
- `ui_in[1]` (loop): High for continuous loop
- `ui_in[2]` (clk_2x): High to double FM frequency
- `ui_in[3]` (pwm_in): External PWM audio input

## Troubleshooting

### Synthesis Errors

```
Error: Module 'xxx' not found
```
- Ensure all source files are in `../src/`
- Check file paths in Makefile

### Timing Violations

```
Critical path fails timing
```
- Reduce target frequency in Makefile
- Check `--freq` parameter in NEXTPNR_OPTS

### Programming Fails

```
Device not found
```
- Check USB connection
- Verify programmer configuration
- Try with sudo/root permissions

## Clean Build

```bash
make clean
```

Removes all generated files:
- JSON netlist
- Config files
- Bitstream
- Log files

## License

Apache 2.0 - See LICENSE file for details.
