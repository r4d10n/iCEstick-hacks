# FM Transmitter Integration Patch

## Apply to ttgf0p2-tone-fm-tx

```bash
cd ttgf0p2-tone-fm-tx
git checkout -b feature/fm-transmitter
git am < /path/to/fm-transmitter-integration.patch
git push -u origin feature/fm-transmitter
gh pr create --title "Add FM transmitter with tone generation" --body "Integrate DDS-based FM transmitter"
```

## What's included

- DDS-based FM transmitter core
- Melody playback with ROM-based sequencer
- External PWM audio input support
- Clock doubling for higher carrier frequencies
- Comprehensive testbench
- Updated module name to tt_um_tone_fm_tx
