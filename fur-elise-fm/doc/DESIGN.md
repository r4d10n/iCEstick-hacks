# Für Elise FM Transmitter - ASIC Design Document

## Project Overview

This document describes a standalone, architecture-independent FM transmitter
that plays Beethoven's "Für Elise" melody. The design is intended for fabrication
on GlobalFoundries GF180MCU process and contains no technology-specific primitives.

## Design Constraints

### Target Technology
- **Process**: GlobalFoundries GF180MCU (180nm)
- **No PLL**: Output frequency derived directly from input clock
- **No Vendor Primitives**: Pure synthesizable Verilog
- **Single Clock Domain**: Simplifies timing closure

### Key Features
- Architecture independent (portable to any ASIC/FPGA)
- Self-contained melody ROM (no external memory)
- Configurable timing parameters
- Single GPIO output for FM signal

## Theory of Operation

### Direct Digital Synthesis (DDS)

The FM transmitter uses a phase accumulator for Direct Digital Synthesis:

```
                    +------------------+
    Phase      +--->|  32-bit Adder    |---+
    Increment  |    +------------------+   |
               |                           |
               |    +------------------+   |
               +----| 32-bit Register  |<--+
                    +------------------+
                            |
                            v
                       MSB (bit 31)
                            |
                            v
                      FM Output
```

**Formula**:
```
phase_increment = (desired_freq / clock_freq) × 2^32
```

The MSB of the accumulator toggles at the desired frequency (with ~1 LSB jitter).

### FM Modulation

For FM transmission, the carrier frequency is modulated by the audio signal:

```
f_out = f_carrier + (audio_sample × deviation_scale)
```

For musical notes, each note corresponds to a specific frequency deviation
from a center carrier frequency.

### Frequency Calculations

**Without PLL**, the output frequency is limited by the input clock:

```
Maximum output frequency = clock_freq / 2  (Nyquist limit)
Practical limit ≈ clock_freq / 4  (for clean signal)
```

**Example with 100 MHz clock**:
- Center frequency: ~25 MHz (quarter of clock)
- Musical note range: ±2 MHz around center
- Phase increment for 25 MHz: (25M / 100M) × 2^32 = 1,073,741,824

**Example with 10 MHz clock**:
- Center frequency: ~2.5 MHz
- Musical note range: ±200 kHz around center

## Musical Implementation

### Note Frequencies (Equal Temperament, A4 = 440 Hz)

The melody uses these notes with their standard frequencies:

| Note | Frequency (Hz) | MIDI Number |
|------|----------------|-------------|
| E5   | 659.26        | 76          |
| D#5  | 622.25        | 75          |
| D5   | 587.33        | 74          |
| C5   | 523.25        | 72          |
| B4   | 493.88        | 71          |
| A4   | 440.00        | 69          |
| G#4  | 415.30        | 68          |
| G4   | 392.00        | 67          |
| E4   | 329.63        | 64          |
| C4   | 261.63        | 60          |
| REST | 0             | 0           |

### FM Encoding Strategy

Rather than encoding absolute frequencies (which would require knowing the clock),
we encode **relative frequency offsets** as signed values:

```
phase_increment = base_increment + (note_offset × scale_factor)
```

Where:
- `base_increment` = Phase increment for center frequency
- `note_offset` = Signed value representing note pitch (-128 to +127)
- `scale_factor` = Configurable frequency scaling

This allows the same melody data to work at any clock frequency.

### Für Elise Melody Encoding

The famous opening theme (simplified):

```
E5 D#5 E5 D#5 E5 B4 D5 C5 A4 (rest)
C4 E4 A4 B4 (rest) E4 G#4 B4 C5 (rest)
E4 E5 D#5 E5 D#5 E5 B4 D5 C5 A4 ...
```

Each note is encoded with:
- 8-bit pitch offset (signed, relative to center)
- Duration index (16th, 8th, quarter, half note, etc.)

## Module Hierarchy

```
fur_elise_fm_top
├── melody_rom          # Note sequence storage
├── melody_sequencer    # Timing and playback control
├── note_to_freq        # Note-to-frequency conversion
└── fm_modulator        # Phase accumulator output
```

## Port Definitions

### Top Level (`fur_elise_fm_top`)

| Port      | Direction | Width | Description                    |
|-----------|-----------|-------|--------------------------------|
| clk       | input     | 1     | System clock                   |
| rst_n     | input     | 1     | Active-low reset               |
| enable    | input     | 1     | Enable playback                |
| loop      | input     | 1     | Loop melody continuously       |
| fm_out    | output    | 1     | FM modulated output            |
| playing   | output    | 1     | Melody currently playing       |
| note_idx  | output    | 8     | Current note index (debug)     |

### Parameters

| Parameter          | Default    | Description                        |
|--------------------|------------|------------------------------------|
| CLK_FREQ_HZ        | 100000000  | Input clock frequency in Hz        |
| CENTER_FREQ_HZ     | 25000000   | Carrier center frequency in Hz     |
| NOTE_DURATION_MS   | 200        | Base note duration in milliseconds |
| FREQ_DEVIATION_HZ  | 100000     | Frequency deviation per semitone   |

## Timing Considerations

### Clock Requirements

The design has minimal timing requirements:
- Single clock domain
- No clock domain crossings
- All flip-flops are standard D-type
- Combinational depth is minimal

### Critical Paths

1. **Phase accumulator addition**: 32-bit carry chain
2. **Note ROM lookup**: Single-cycle read
3. **Frequency calculation**: Multiplication (can be pipelined if needed)

### Reset Strategy

- Synchronous reset (rst_n synchronized internally)
- All registers have defined reset values
- Clean startup guaranteed

## Synthesis Guidelines

### For GF180MCU

```tcl
# Target frequency guidance
set_max_delay 10.0 -from [all_inputs] -to [all_outputs]

# Area optimization (melody ROM will dominate)
set_max_area 0

# No clock gating (keep it simple)
set_clock_gating_style none
```

### Resource Estimates

- **Flip-flops**: ~200 (counters, state machines, accumulator)
- **LUTs/Logic**: ~500 (ROM, arithmetic)
- **No RAM**: All storage in flip-flops/LUTs
- **Estimated Area**: < 0.1 mm² in GF180

## Verification Plan

1. **Unit Tests**: Each module tested independently
2. **Integration Test**: Full melody playback simulation
3. **Frequency Verification**: Check output frequency spectrum
4. **Timing Simulation**: Verify note durations

## Files

```
fur-elise-fm/
├── rtl/
│   ├── fur_elise_fm_top.v      # Top-level module
│   ├── melody_rom.v            # Note sequence ROM
│   ├── melody_sequencer.v      # Playback controller
│   ├── note_to_freq.v          # Frequency converter
│   └── fm_modulator.v          # DDS FM output
├── tb/
│   └── fur_elise_fm_tb.v       # Testbench
├── doc/
│   └── DESIGN.md               # This document
└── constraints/
    └── gf180_constraints.sdc   # Timing constraints
```

## References

1. Hamsterworks FM Transmitter: http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS
2. Direct Digital Synthesis: https://en.wikipedia.org/wiki/Direct_digital_synthesis
3. Musical Note Frequencies: https://pages.mtu.edu/~suits/notefreqs.html
4. GF180MCU PDK: https://github.com/google/gf180mcu-pdk

## Revision History

| Rev | Date       | Author | Description                |
|-----|------------|--------|----------------------------|
| 1.0 | 2025-01-21 | -      | Initial design document    |
