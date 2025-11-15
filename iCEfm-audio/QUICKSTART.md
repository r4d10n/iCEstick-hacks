# Quick Start Guide - FM Audio Transmitter

Get up and running in 5 minutes!

## Prerequisites

1. **FPGA Board** - One of:
   - iCE40-HX8K (iCEstick)
   - iCE40-UP5K (UPduino, iCEBreaker)
   - ECP5 (ULX3S, OrangeCrab)

2. **Software Installed**:
   ```bash
   # FPGA tools
   sudo apt-get install yosys nextpnr-ice40 icestorm  # For iCE40
   # OR
   sudo apt-get install yosys nextpnr-ecp5 prjtrellis  # For ECP5

   # Python dependencies
   pip install -r requirements.txt

   # Audio tools
   sudo apt-get install ffmpeg
   ```

## Step-by-Step

### 1. Build FPGA Bitstream

Choose your FPGA and run:

```bash
# For iCE40-HX8K (iCEstick)
make -f Makefile.ice40hx8k

# For iCE40-UP5K (UPduino/iCEBreaker)
make -f Makefile.ice40up5k

# For ECP5 (ULX3S/OrangeCrab)
make -f Makefile.ecp5
```

### 2. Edit Pin Assignments (if needed)

Check `pcf/` directory and verify pins match your board:
- `ice40hx8k.pcf` - for HX8K boards
- `ice40up5k.pcf` - for UP5K boards
- `ecp5.lpf` - for ECP5 boards

Common pins to verify:
- `clk_in` - Board clock input
- `uart_rx` - UART receive pin
- `antenna` - FM output pin

### 3. Program FPGA

```bash
# iCE40 boards
make -f Makefile.ice40hx8k prog
# (or sudo-prog if permission needed)

# ECP5 boards
make -f Makefile.ecp5 prog
```

**Check LEDs:**
- LED 1 (PLL Lock) - Should be ON
- LED 2 (Configured) - OFF until UART config received
- LED 3 (Active) - OFF until audio streaming

### 4. Connect Antenna

Attach a wire to the `antenna` pin:
- **For testing**: 10-15 cm wire
- **Better reception**: 75 cm (quarter-wave at 100 MHz)

**WARNING**: Do not use long antennas without proper shielding. This is for educational purposes only!

### 5. Connect UART

Find your serial port:
```bash
# Linux
ls /dev/ttyUSB*
# or
ls /dev/ttyACM*

# macOS
ls /dev/cu.usb*

# Windows
# Check Device Manager for COMx port
```

### 6. Stream Audio

```bash
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i your_music.mp3
```

Replace:
- `/dev/ttyUSB0` with your serial port
- `91.0` with desired FM frequency (88-108 MHz)
- `your_music.mp3` with your audio file

**First-time use?** Try:
```bash
# Download a test audio file
wget https://www.kozco.com/tech/piano2.wav

# Stream it at 91.0 MHz
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i piano2.wav
```

### 7. Tune FM Receiver

1. Turn on FM radio or use smartphone FM app
2. Tune to your configured frequency (e.g., 91.0 MHz)
3. Place receiver close to FPGA (within 1-2 meters)
4. You should hear your audio!

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| No signal | Check PLL lock LED, verify antenna, reduce distance |
| Build errors | Install required tools, check pin constraints |
| Serial errors | Verify port name, check permissions (`sudo` may be needed) |
| Poor quality | Use higher clock frequency, check audio file quality |
| LEDs not working | Check pin assignments in PCF file |

## Example Commands

**Test different frequencies:**
```bash
# Bottom of FM band
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 88.1 -i music.mp3

# Middle of FM band
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 98.5 -i music.mp3

# Top of FM band
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 107.9 -i music.mp3
```

**Custom deviation (narrowband FM):**
```bash
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -d 25 -i music.mp3
```

**Different baud rate:**
```bash
python scripts/stream_audio.py -p /dev/ttyUSB0 -f 91.0 -b 230400 -i music.mp3
# Note: Also change BAUD_RATE in fm_audio_top.v and rebuild
```

## Next Steps

- Read full [README.md](README.md) for detailed information
- Experiment with different frequencies and audio files
- Try adjusting the deviation for different sound characteristics
- Check resource usage: `make -f Makefile.ice40hx8k show-usage`
- Explore the code in `rtl/` directory

## Support

Issues or questions? Check:
1. README.md - Full documentation
2. Pin constraint files - Verify pins match your board
3. Python script help: `python scripts/stream_audio.py --help`

## Legal Reminder

**Broadcasting on FM frequencies may be illegal without a license!**
This project is for educational purposes only. Use responsibly.

---

Happy transmitting! 📻🎵
