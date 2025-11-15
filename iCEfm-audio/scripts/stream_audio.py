#!/usr/bin/env python3
"""
FM Audio Streamer
Processes audio files (MP3, WAV, etc.) and streams to FPGA via UART

Author: Based on iCEstick-hacks FM transmitter project
License: MIT

Requirements:
    pip install pydub pyserial numpy

Usage:
    python stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i audio.mp3
    python stream_audio.py --port COM3 --freq 100.5 --input music.wav
"""

import argparse
import struct
import sys
import time
import numpy as np

try:
    import serial
except ImportError:
    print("Error: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

try:
    from pydub import AudioSegment
except ImportError:
    print("Error: pydub not installed. Run: pip install pydub")
    print("Note: Also requires ffmpeg installed on your system")
    sys.exit(1)


class FMTransmitter:
    """FM Transmitter UART Interface"""

    # PLL output frequency in Hz (must match FPGA configuration)
    PLL_FREQ = 255_000_000

    # Sample rate for audio (must match FPGA)
    SAMPLE_RATE = 48000

    # Default FM deviation (±75 kHz for wideband FM)
    DEFAULT_DEVIATION = 75000

    def __init__(self, port, baud_rate=115200, timeout=1):
        """
        Initialize UART connection

        Args:
            port: Serial port (e.g., '/dev/ttyUSB0', 'COM3')
            baud_rate: UART baud rate (default: 115200)
            timeout: Serial timeout in seconds
        """
        try:
            self.serial = serial.Serial(port, baud_rate, timeout=timeout)
            print(f"Connected to {port} at {baud_rate} baud")
        except serial.SerialException as e:
            print(f"Error opening serial port: {e}")
            sys.exit(1)

    def calculate_phase_increment(self, frequency_mhz):
        """
        Calculate phase increment for desired carrier frequency

        Formula: phase_inc = (desired_freq_Hz / PLL_FREQ) * 2^32

        Args:
            frequency_mhz: Desired carrier frequency in MHz

        Returns:
            32-bit phase increment value
        """
        freq_hz = frequency_mhz * 1_000_000
        phase_inc = int((freq_hz / self.PLL_FREQ) * (2**32))

        # Ensure it's within 32-bit range
        phase_inc = phase_inc & 0xFFFFFFFF

        print(f"Carrier frequency: {frequency_mhz} MHz")
        print(f"Phase increment: {phase_inc} (0x{phase_inc:08X})")

        return phase_inc

    def calculate_deviation_scale(self, deviation_hz=DEFAULT_DEVIATION):
        """
        Calculate deviation scale factor

        Formula: deviation_scale = (deviation_Hz / PLL_FREQ) * 2^32 / 32768

        Args:
            deviation_hz: Frequency deviation in Hz (default: 75 kHz)

        Returns:
            32-bit deviation scale value
        """
        deviation_scale = int((deviation_hz / self.PLL_FREQ) * (2**32) / 32768)

        # Ensure it's within 32-bit range
        deviation_scale = deviation_scale & 0xFFFFFFFF

        print(f"Frequency deviation: ±{deviation_hz/1000} kHz")
        print(f"Deviation scale: {deviation_scale} (0x{deviation_scale:08X})")

        return deviation_scale

    def configure(self, frequency_mhz, deviation_hz=DEFAULT_DEVIATION):
        """
        Send configuration to FPGA

        Args:
            frequency_mhz: Carrier frequency in MHz
            deviation_hz: Frequency deviation in Hz
        """
        phase_inc = self.calculate_phase_increment(frequency_mhz)
        deviation_scale = self.calculate_deviation_scale(deviation_hz)

        # Build configuration packet
        # Byte 0: Command (0xC0 = Configure)
        # Bytes 1-4: Phase increment (little-endian)
        # Bytes 5-8: Deviation scale (little-endian)
        config_data = struct.pack('<B', 0xC0)  # Command byte
        config_data += struct.pack('<I', phase_inc)  # 32-bit phase increment
        config_data += struct.pack('<I', deviation_scale)  # 32-bit deviation scale

        print(f"\nSending configuration ({len(config_data)} bytes)...")
        self.serial.write(config_data)
        self.serial.flush()
        time.sleep(0.1)  # Wait for FPGA to process
        print("Configuration sent!")

    def stream_audio(self, audio_file, verbose=False):
        """
        Process and stream audio file to FPGA

        Args:
            audio_file: Path to audio file (MP3, WAV, etc.)
            verbose: Print detailed progress information
        """
        print(f"\nLoading audio file: {audio_file}")

        try:
            # Load audio file using pydub
            audio = AudioSegment.from_file(audio_file)
        except Exception as e:
            print(f"Error loading audio file: {e}")
            return

        print(f"Original format: {audio.channels} channels, {audio.frame_rate} Hz, {audio.sample_width*8}-bit")

        # Convert to mono, 48 kHz, 16-bit
        audio = audio.set_channels(1)  # Mono
        audio = audio.set_frame_rate(self.SAMPLE_RATE)  # 48 kHz
        audio = audio.set_sample_width(2)  # 16-bit

        print(f"Converted to: 1 channel, {self.SAMPLE_RATE} Hz, 16-bit")
        print(f"Duration: {len(audio)/1000:.2f} seconds")
        print(f"Total samples: {len(audio.get_array_of_samples())}")

        # Get audio samples as numpy array
        samples = np.array(audio.get_array_of_samples(), dtype=np.int16)

        # Stream samples to FPGA
        print(f"\nStreaming audio...")
        total_samples = len(samples)
        chunk_size = 1024  # Send in chunks for better performance

        start_time = time.time()
        bytes_sent = 0

        for i in range(0, total_samples, chunk_size):
            chunk = samples[i:i+chunk_size]

            # Pack samples as 16-bit signed integers (little-endian)
            data = struct.pack(f'<{len(chunk)}h', *chunk)
            self.serial.write(data)
            bytes_sent += len(data)

            # Progress indicator
            if verbose or (i % (chunk_size * 10) == 0):
                progress = (i / total_samples) * 100
                elapsed = time.time() - start_time
                if elapsed > 0:
                    rate = bytes_sent / elapsed / 1024
                    print(f"\rProgress: {progress:.1f}% ({i}/{total_samples} samples, {rate:.1f} KB/s)", end='')

        self.serial.flush()
        elapsed = time.time() - start_time

        print(f"\n\nStreaming complete!")
        print(f"Sent {bytes_sent} bytes in {elapsed:.2f} seconds")
        print(f"Average rate: {bytes_sent/elapsed/1024:.1f} KB/s")

    def close(self):
        """Close serial connection"""
        if self.serial.is_open:
            self.serial.close()
            print("\nSerial port closed")


def main():
    parser = argparse.ArgumentParser(
        description='Stream audio to FPGA FM transmitter via UART',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Stream MP3 to 91.0 MHz
  python stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i music.mp3

  # Stream WAV to 100.5 MHz with custom deviation
  python stream_audio.py -p COM3 -f 100.5 -d 50 -i audio.wav

  # Verbose output
  python stream_audio.py -p /dev/ttyUSB0 -f 91.0 -i song.mp3 -v

Note: Ensure FPGA is programmed and connected before running.
      Use frequencies in the FM broadcast band (88-108 MHz) for testing.
        """
    )

    parser.add_argument('-p', '--port', required=True,
                        help='Serial port (e.g., /dev/ttyUSB0, COM3)')
    parser.add_argument('-f', '--freq', type=float, required=True,
                        help='Carrier frequency in MHz (e.g., 91.0)')
    parser.add_argument('-i', '--input', required=True,
                        help='Input audio file (MP3, WAV, etc.)')
    parser.add_argument('-d', '--deviation', type=float, default=75,
                        help='Frequency deviation in kHz (default: 75)')
    parser.add_argument('-b', '--baud', type=int, default=115200,
                        help='UART baud rate (default: 115200)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')

    args = parser.parse_args()

    # Validate frequency (FM broadcast band: 88-108 MHz)
    if args.freq < 88 or args.freq > 108:
        print(f"Warning: Frequency {args.freq} MHz is outside FM broadcast band (88-108 MHz)")
        response = input("Continue anyway? (y/n): ")
        if response.lower() != 'y':
            sys.exit(0)

    # Create transmitter instance
    tx = FMTransmitter(args.port, args.baud)

    try:
        # Configure FPGA
        tx.configure(args.freq, args.deviation * 1000)  # Convert kHz to Hz

        # Stream audio
        tx.stream_audio(args.input, args.verbose)

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    except Exception as e:
        print(f"\nError: {e}")
    finally:
        tx.close()


if __name__ == '__main__':
    main()
