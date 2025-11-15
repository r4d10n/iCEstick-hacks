# FM Audio Transmitter for FPGA

A generic Verilog implementation of an FM transmitter that streams audio via UART. Compatible with iCE40-HX8K, iCE40-UP5K, and Lattice ECP5 FPGAs.

**WARNING: This is an educational project. Broadcasting on FM frequencies may be illegal in your country without proper licensing. Use responsibly and only for testing in controlled environments.**

## Overview

This project implements a Direct Digital Synthesis (DDS) based FM transmitter that:
- Receives audio data via UART from a PC
- Modulates the audio onto a configurable carrier frequency
- Outputs an FM signal via a GPIO pin connected to an antenna
- Supports MP3, WAV, and other audio formats (converted on PC side)

The design is based on the phase accumulator approach described by Mike Field (Hamsterworks).

## Features

- **Multi-FPGA Support**: Compatible with iCE40-HX8K, iCE40-UP5K, and ECP5
- **UART Interface**: 115200 baud serial communication
- **Configurable Frequency**: Set carrier frequency via UART (e.g., 88-108 MHz FM band)
- **Audio Streaming**: Real-time audio transmission from PC
- **Python Utility**: Easy-to-use script for processing and streaming audio files
- **High Quality**: 48 kHz sample rate, ±75 kHz deviation (wideband FM)

## How It Works

### The DDS FM Modulator

The core uses a 32-bit phase accumulator running at high speed (240-320 MHz):

1. Each clock cycle, a phase increment is added to the accumulator
2. The phase increment is calculated as: `(desired_freq / clock_freq) * 2^32`
3. The MSB (bit 31) of the accumulator toggles at the desired frequency
4. Audio modulation is achieved by varying the phase increment based on the audio sample

This creates a jittery pulse train at the carrier frequency, with frequency modulation corresponding to the audio signal.

### Frequency Calculation Examples

For a 255 MHz clock:

```
Center frequency (91.0 MHz):
  phase_inc = (91,000,000 / 255,000,000) * 2^32 = 1,538,160,066

FM deviation (±75 kHz):
  deviation_scale = (75,000 / 255,000,000) * 2^32 / 32768 = 39,406
```

The Python script calculates these automatically.

## Hardware Requirements

### Supported FPGA Boards

- **iCE40-HX8K**: iCEstick, BlackIce, or similar
- **iCE40-UP5K**: UPduino v3.0, iCEBreaker
- **Lattice ECP5**: ULX3S, OrangeCrab

### Additional Components

- USB-UART adapter (if not integrated on board)
- Wire antenna (10-15 cm for testing, ~75 cm for quarter-wave at 100 MHz)
- FM receiver (radio, RTL-SDR, or smartphone with FM app)

## Software Requirements

### FPGA Toolchain

**For iCE40:**
```bash
# Install open-source toolchain
sudo apt-get install yosys arachne-pnr icestorm
# Or for UP5K (requires nextpnr):
sudo apt-get install yosys nextpnr-ice40 icestorm
```

**For ECP5:**
```bash
sudo apt-get install yosys nextpnr-ecp5 prjtrellis
```

### Python Dependencies

```bash
pip install pydub pyserial numpy
```

Also requires `ffmpeg` for audio format conversion:
```bash
sudo apt-get install ffmpeg  # Linux
brew install ffmpeg          # macOS
```

## Building and Programming

### 1. Clone Repository

```bash
cd iCEfm-audio
```

### 2. Build for Your FPGA

**iCE40-HX8K:**
```bash
make -f Makefile.ice40hx8k
```

**iCE40-UP5K:**
```bash
make -f Makefile.ice40up5k
```

**ECP5:**
```bash
make -f Makefile.ecp5
```

### 3. Program FPGA

**iCE40:**
```bash
make -f Makefile.ice40hx8k prog
# Or with sudo if needed:
make -f Makefile.ice40hx8k sudo-prog
```

**ECP5:**
```bash
make -f Makefile.ecp5 prog
```

## Usage

### 1. Connect Hardware

1. Program your FPGA with the bitstream
2. Connect a 10-15 cm wire to the `antenna` pin (see PCF files for pin numbers)
3. Connect UART (USB-serial) to the `uart_rx` pin
4. Power on the FPGA

### 2. Stream Audio

**Basic usage:**
```bash
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i music.mp3
```

**With custom settings:**
```bash
# Different frequency and deviation
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 100.5 -d 50 -i audio.wav

# Windows COM port
python scripts/stream_audio.py -p COM3 -f 91.0 -i song.mp3

# Verbose output
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i audio.mp3 -v
```

**Parameters:**
- `-p, --port`: Serial port (e.g., `/dev/ttyUSB0`, `COM3`)
- `-f, --freq`: Carrier frequency in MHz (e.g., `91.0`)
- `-i, --input`: Audio file (MP3, WAV, FLAC, etc.)
- `-d, --deviation`: Frequency deviation in kHz (default: 75)
- `-b, --baud`: UART baud rate (default: 115200)
- `-v, --verbose`: Verbose output

### 3. Tune FM Receiver

1. Set your FM radio to the configured frequency (e.g., 91.0 MHz)
2. Place receiver near FPGA (within 1-2 meters for short antenna)
3. Adjust frequency if needed for best reception

## Project Structure

```
iCEfm-audio/
├── rtl/                        # Verilog source files
│   ├── fm_audio_top.v         # Top-level module
│   ├── uart_rx.v              # UART receiver
│   ├── pll_wrapper.v          # Multi-FPGA PLL wrapper
│   ├── fm_transmitter.v       # FM modulator core
│   └── fifo.v                 # Audio sample buffer
├── pcf/                        # Pin constraint files
│   ├── ice40hx8k.pcf          # iCE40-HX8K pins
│   ├── ice40up5k.pcf          # iCE40-UP5K pins
│   └── ecp5.lpf               # ECP5 pins
├── scripts/                    # Python utilities
│   └── stream_audio.py        # Audio streaming script
├── Makefile.ice40hx8k         # Build for HX8K
├── Makefile.ice40up5k         # Build for UP5K
├── Makefile.ecp5              # Build for ECP5
└── README.md                  # This file
```

## UART Protocol

### Configuration Phase (9 bytes)

| Byte | Description |
|------|-------------|
| 0    | Command (`0xC0` = Configure) |
| 1-4  | Center frequency phase increment (32-bit, little-endian) |
| 5-8  | Deviation scale factor (32-bit, little-endian) |

### Audio Streaming Phase

- Continuous stream of 16-bit signed audio samples
- Little-endian byte order (low byte, high byte)
- 48 kHz sample rate

The Python script handles this protocol automatically.

## Customization

### Changing Clock Frequency

Edit `pll_wrapper.v` and adjust PLL parameters for your desired output frequency. Higher frequencies provide better signal quality.

### Adjusting Pin Assignments

Edit the appropriate PCF/LPF file in the `pcf/` directory to match your board layout.

### Changing Sample Rate

Modify `SAMPLE_PERIOD` calculation in `fm_transmitter.v`:
```verilog
localparam SAMPLE_PERIOD = CLOCK_FREQ_MHZ * 1_000_000 / DESIRED_SAMPLE_RATE;
```

## Troubleshooting

### No Signal Received

1. Check PLL lock LED - should be ON
2. Verify antenna connection
3. Try increasing antenna length
4. Check carrier frequency matches receiver
5. Reduce distance between transmitter and receiver

### Poor Audio Quality

1. Increase PLL frequency (240-320 MHz recommended)
2. Check for buffer underruns (LED indicators)
3. Verify audio file quality
4. Try different deviation settings

### UART Errors

1. Verify baud rate matches (115200)
2. Check RX pin connection
3. Ensure proper ground connection
4. Try different USB-UART adapter

### Build Errors

1. Ensure all tools are installed (`yosys`, `nextpnr`, etc.)
2. Check FPGA family macro is defined correctly
3. Verify pin assignments in PCF/LPF file

## Legal Notice

**IMPORTANT**: Broadcasting on FM frequencies without a license is illegal in most countries. This project is for:
- Educational purposes
- Testing in RF-shielded environments
- Licensed amateur radio use (check your local regulations)
- Short-range testing with minimal antenna

Always comply with your local radio frequency regulations.

## Technical Details

### Signal Characteristics

- **Modulation**: Wideband FM (WBFM)
- **Deviation**: ±75 kHz (configurable)
- **Audio Bandwidth**: ~20 kHz
- **Sample Rate**: 48 kHz
- **Bit Depth**: 16-bit signed
- **Output**: Single-bit PWM-like signal at carrier frequency

### Phase Accumulator

The phase accumulator is a 32-bit counter that overflows to create the carrier:
```
output_signal = phase_accumulator[31]
phase_accumulator += phase_increment + (audio_sample * deviation_scale)
```

Jitter: ~3-4 ns (depends on clock frequency)

### Resource Usage

Approximate resource usage on iCE40-HX8K:
- Logic cells: ~800-1000
- Block RAM: 4-8 blocks (for FIFO)
- PLLs: 1

## Credits

- Based on original work by Mike Field (Hamsterworks): http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS
- iCEstick example by Rakesh Peter
- Inspired by various FPGA FM transmitter projects

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please:
1. Test on your hardware
2. Document any changes
3. Follow existing code style
4. Add comments for complex logic

## References

- [Hamsterworks FM Transmitter](http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS)
- [Direct Digital Synthesis](https://en.wikipedia.org/wiki/Direct_digital_synthesis)
- [FM Broadcasting](https://en.wikipedia.org/wiki/FM_broadcasting)
- [iCE40 Documentation](http://www.latticesemi.com/iCE40)
- [ECP5 Documentation](http://www.latticesemi.com/ecp5)
