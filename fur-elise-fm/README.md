# Für Elise FM Transmitter - ASIC Design

A standalone, architecture-independent Verilog implementation of an FM transmitter
that plays Beethoven's "Für Elise" melody. Designed for fabrication on the
GlobalFoundries GF180MCU process.

## Features

- **No PLL Required**: Output frequency derived directly from input clock
- **Architecture Independent**: Pure behavioral Verilog, no vendor primitives
- **Self-Contained**: Melody stored in synthesizable ROM (no external memory)
- **Configurable**: Tempo, carrier frequency, and FM deviation are parameterized
- **Single Clock Domain**: Simplifies timing closure for ASIC

## Quick Start

### Simulation (Icarus Verilog)

```bash
cd tb
iverilog -o fur_elise_tb fur_elise_fm_tb.v ../rtl/*.v
vvp fur_elise_tb
gtkwave fur_elise_fm_tb.vcd
```

### Synthesis (Example with Yosys)

```bash
cd rtl
yosys -p "read_verilog *.v; synth -top fur_elise_fm_top; write_verilog synth.v"
```

## Theory of Operation

### Direct Digital Synthesis (DDS)

The design uses a 32-bit phase accumulator running at the input clock frequency:

```
+------------------+
|  Phase           |
|  Accumulator     |---> MSB = FM Output
|  (32-bit)        |
+------------------+
        ^
        |
+------------------+
|  Phase Increment |
|  (varies with    |
|   note pitch)    |
+------------------+
```

Each clock cycle, a phase increment value is added to the accumulator. The MSB
toggles at the desired output frequency:

```
output_frequency = (phase_increment / 2^32) × clock_frequency
```

### FM Modulation

Musical notes are encoded as FM frequency deviations around a carrier:

```
phase_increment = base_increment + (note_offset × deviation_per_semitone)
```

Where:
- `base_increment` sets the carrier (center) frequency
- `note_offset` is the musical pitch (semitones from A4)
- `deviation_per_semitone` controls FM deviation width

## Parameter Configuration

### Clock Frequency Examples

| Clock (MHz) | CLOCKS_PER_16TH | BASE_PHASE_INC | Center Freq (MHz) |
|-------------|-----------------|----------------|-------------------|
| 10          | 1,250,000       | 0x40000000     | 2.5               |
| 50          | 6,250,000       | 0x40000000     | 12.5              |
| 100         | 12,500,000      | 0x40000000     | 25.0              |
| 200         | 25,000,000      | 0x40000000     | 50.0              |

### Tempo Adjustment

Default is 120 BPM. For different tempos:

```
CLOCKS_PER_16TH = clock_freq / (BPM / 60 × 4)
```

Examples (100 MHz clock):
- 60 BPM:  25,000,000
- 90 BPM:  16,666,667
- 120 BPM: 12,500,000
- 180 BPM: 8,333,333

### Carrier Frequency

Adjust `BASE_PHASE_INCREMENT` to change center frequency:

```
BASE_PHASE_INCREMENT = (center_freq / clock_freq) × 2^32
```

| Ratio (center/clock) | BASE_PHASE_INCREMENT |
|----------------------|----------------------|
| 1/2 (max practical)  | 0x80000000           |
| 1/4 (default)        | 0x40000000           |
| 1/8                  | 0x20000000           |
| 1/16                 | 0x10000000           |

## Module Hierarchy

```
fur_elise_fm_top
├── melody_rom          # 82-note Für Elise sequence
├── melody_sequencer    # Timing control, note stepping
├── note_to_phase_inc   # Pitch to frequency conversion
└── fm_modulator        # 32-bit DDS output stage
```

## Pin Description

| Pin         | Dir | Width | Description                    |
|-------------|-----|-------|--------------------------------|
| clk         | in  | 1     | System clock                   |
| rst_n       | in  | 1     | Active-low asynchronous reset  |
| enable      | in  | 1     | Enable melody playback         |
| loop        | in  | 1     | Loop melody continuously       |
| fm_out      | out | 1     | FM modulated output            |
| playing     | out | 1     | Melody currently playing       |
| melody_end  | out | 1     | Pulse at end of melody         |
| note_index  | out | 7     | Current note index (debug)     |

## Resource Estimates

For GF180MCU (180nm):

- **Flip-flops**: ~200 (accumulators, counters, state)
- **Logic Gates**: ~2000 (ROM, arithmetic, control)
- **Estimated Area**: < 0.1 mm²
- **No SRAM**: All storage synthesized to gates

## File Structure

```
fur-elise-fm/
├── rtl/
│   ├── fur_elise_fm_top.v      # Top-level integration
│   ├── melody_rom.v            # Note sequence ROM
│   ├── melody_sequencer.v      # Playback timing
│   └── fm_modulator.v          # DDS + frequency conversion
├── tb/
│   └── fur_elise_fm_tb.v       # Comprehensive testbench
├── constraints/
│   └── gf180_constraints.sdc   # Timing constraints
├── doc/
│   └── DESIGN.md               # Detailed design document
└── README.md                   # This file
```

## GF180MCU Integration Notes

1. **Standard Cells Only**: No SRAM or custom macros required
2. **Timing Critical Path**: 32-bit adder in phase accumulator
3. **Recommended Frequency**: ≤ 100 MHz for comfortable timing margin
4. **Power**: Low power due to simple logic (mostly idle counters)
5. **Output Pad**: Use high-speed capable I/O for fm_out

## How to Receive the Signal

Without a PLL, the output frequency depends on your input clock:

1. **With 100 MHz clock**: FM output around 25 MHz
   - Use SDR receiver or spectrum analyzer
   - Not in commercial FM band

2. **With 400 MHz clock** (if supported): FM output around 100 MHz
   - Could be received on FM radio (88-108 MHz band)
   - **Warning**: Unlicensed transmission is illegal

3. **Best approach**: Use oscilloscope or logic analyzer
   - Observe frequency modulation directly
   - Verify note pitch changes

## The Melody

Beethoven's "Für Elise" (Bagatelle No. 25 in A minor, WoO 59)

The ROM contains the famous A-section theme:
```
E5 D#5 E5 D#5 E5 B4 D5 C5 A4...
(repeated twice with variations)
```

82 notes total, approximately 20 seconds at 120 BPM.

## Legal Notice

This design is for educational and experimental purposes only.
Broadcasting on radio frequencies without appropriate licensing is illegal
in most jurisdictions. Use responsibly in shielded environments or at
frequencies that don't interfere with licensed services.

## License

MIT License - See LICENSE file for details.

## References

1. [Hamsterworks FM Transmitter](http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS)
2. [Direct Digital Synthesis](https://en.wikipedia.org/wiki/Direct_digital_synthesis)
3. [GF180MCU PDK](https://github.com/google/gf180mcu-pdk)
4. [OpenLane ASIC Flow](https://github.com/The-OpenROAD-Project/OpenLane)
