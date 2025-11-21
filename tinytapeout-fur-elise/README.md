# Für Elise FM Transmitter - TinyTapeout GF180

A TinyTapeout-compatible Verilog implementation of an FM transmitter that plays
Beethoven's "Für Elise" melody. Designed for the GF180MCU process.

## Features

- **Direct Digital Synthesis (DDS)**: 32-bit phase accumulator for precise frequency generation
- **FM Modulation**: Musical notes modulate the carrier frequency
- **82-note Melody ROM**: Complete Für Elise A-section theme
- **PWM Audio Input**: External audio via PWM for FM transmission
- **Clock Doubling**: XOR-based frequency doubling for higher carrier frequencies
- **Audio Output**: Direct speaker output for audible melody playback

## Pin Mapping

### Inputs (ui_in)

| Pin | Name | Description |
|-----|------|-------------|
| ui[0] | enable | Enable playback (active high) |
| ui[1] | loop | Loop melody continuously |
| ui[2] | clk_2x_enable | Enable clock doubling |
| ui[3] | pwm_in | External PWM audio input |
| ui[7:4] | reserved | Unused |

### Outputs (uo_out)

| Pin | Name | Description |
|-----|------|-------------|
| uo[0] | fm_out | FM modulated RF output |
| uo[1] | audio_out | Audio frequency output (speaker) |
| uo[2] | playing | Melody currently playing |
| uo[3] | melody_end | Pulse at end of melody |
| uo[7:4] | note_index[3:0] | Current note index (debug) |

### Bidirectional IOs (uio)

| Pin | Name | Description |
|-----|------|-------------|
| uio[7:0] | phase_inc[31:24] | Phase increment MSB (output) |

All bidirectional pins are configured as outputs.

## How It Works

### Direct Digital Synthesis

The design uses a 32-bit phase accumulator running at the system clock:

```
output_frequency = (phase_increment / 2^32) × clock_frequency
```

With a 50 MHz clock and default settings:
- Carrier frequency: ~12.5 MHz
- With clock doubling: ~25 MHz

### FM Modulation

Musical notes are encoded as frequency deviations around the carrier:

```
phase_increment = base_increment + (note_offset × deviation_per_semitone)
```

### Operating Modes

1. **Melody Mode** (default): Plays built-in Für Elise melody
2. **PWM Input Mode**: External PWM audio modulates FM carrier

## Testing

### Simulation (Icarus Verilog)

```bash
cd test
iverilog -o tb tb.v ../src/*.v
vvp tb
gtkwave tb.vcd
```

### Expected Output

```
================================================
TinyTapeout Fur Elise FM Testbench
================================================

[TEST 1] Reset behavior...
  PASS: Clean reset state
[TEST 2] Enable playback...
  PASS: Melody playback active
[TEST 3] FM output activity...
  PASS: FM output toggling
...
ALL TESTS PASSED
================================================
```

## Module Hierarchy

```
tt_um_fur_elise_fm (TinyTapeout wrapper)
└── fur_elise_fm_top
    ├── clock_doubler       # XOR-based clock frequency doubler
    ├── pwm_input_decoder   # PWM to audio sample converter
    ├── melody_rom          # 82-note Für Elise sequence
    ├── melody_sequencer    # Timing control, note stepping
    ├── note_to_phase_inc   # Pitch to frequency conversion
    ├── fm_modulator        # 32-bit DDS output stage
    └── audio_tone_generator # Audio frequency output
```

## Resource Estimates

For GF180MCU (180nm):
- **Flip-flops**: ~200
- **Logic Gates**: ~2000
- **Estimated Area**: < 0.1 mm²

## Legal Notice

This design is for educational and experimental purposes only.
Broadcasting on radio frequencies without appropriate licensing is illegal
in most jurisdictions.

## License

Apache 2.0 - See LICENSE file for details.
