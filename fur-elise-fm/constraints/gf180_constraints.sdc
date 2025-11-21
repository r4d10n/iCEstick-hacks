#-----------------------------------------------------------------------------
# SDC Constraints File for Für Elise FM Transmitter
# Target: GlobalFoundries GF180MCU ASIC Process
#
# This file defines timing constraints for synthesis and place & route.
# Adjust CLK_PERIOD based on your target clock frequency.
#
# Author: Based on iCEstick-hacks FM transmitter project
# License: MIT
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Clock Definition
#-----------------------------------------------------------------------------
# Define the primary clock
# Adjust period based on your target frequency:
#   100 MHz: 10.0 ns
#   50 MHz:  20.0 ns
#   25 MHz:  40.0 ns
#   10 MHz:  100.0 ns

set CLK_PERIOD 10.0
set CLK_NAME clk

create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports clk]

# Clock uncertainty (jitter + skew)
# Conservative value for ASIC
set_clock_uncertainty 0.5 [get_clocks $CLK_NAME]

# Clock transition time
set_clock_transition 0.2 [get_clocks $CLK_NAME]

#-----------------------------------------------------------------------------
# Reset Constraints
#-----------------------------------------------------------------------------
# Async reset - no timing path from reset to clock
set_false_path -from [get_ports rst_n]

#-----------------------------------------------------------------------------
# Input Constraints
#-----------------------------------------------------------------------------
# Input delay relative to clock
# Assumes inputs are registered externally

set INPUT_DELAY 2.0

set_input_delay -clock $CLK_NAME $INPUT_DELAY [get_ports enable]
set_input_delay -clock $CLK_NAME $INPUT_DELAY [get_ports loop]

# Input transition time
set_input_transition 0.5 [get_ports {enable loop}]

#-----------------------------------------------------------------------------
# Output Constraints
#-----------------------------------------------------------------------------
# Output delay relative to clock
# FM output goes directly to pad

set OUTPUT_DELAY 2.0

set_output_delay -clock $CLK_NAME $OUTPUT_DELAY [get_ports fm_out]
set_output_delay -clock $CLK_NAME $OUTPUT_DELAY [get_ports playing]
set_output_delay -clock $CLK_NAME $OUTPUT_DELAY [get_ports melody_end]
set_output_delay -clock $CLK_NAME $OUTPUT_DELAY [get_ports {note_index[*]}]

# Output load (typical pad capacitance)
set_load 5.0 [get_ports fm_out]
set_load 5.0 [get_ports playing]
set_load 5.0 [get_ports melody_end]
set_load 5.0 [get_ports {note_index[*]}]

#-----------------------------------------------------------------------------
# Design Rule Constraints
#-----------------------------------------------------------------------------
# Maximum transition time
set_max_transition 1.0 [current_design]

# Maximum fanout
set_max_fanout 20 [current_design]

# Maximum capacitance
set_max_capacitance 0.5 [current_design]

#-----------------------------------------------------------------------------
# Area Constraints
#-----------------------------------------------------------------------------
# Optimize for area (melody ROM will dominate)
# set_max_area 0

#-----------------------------------------------------------------------------
# Critical Paths
#-----------------------------------------------------------------------------
# The phase accumulator addition is the critical path
# 32-bit carry chain must complete in one clock cycle

# If timing fails, consider:
# 1. Reducing clock frequency
# 2. Pipelining the accumulator (adds latency)
# 3. Using faster cells (if available)

#-----------------------------------------------------------------------------
# False Paths and Multicycle Paths
#-----------------------------------------------------------------------------
# The melody ROM is single-cycle read
# No multicycle paths needed

# Note: If using pipelined multiplication in note_to_phase_increment,
# add appropriate multicycle constraints here

#-----------------------------------------------------------------------------
# Operating Conditions
#-----------------------------------------------------------------------------
# GF180MCU typical operating conditions
# Adjust based on your corner requirements

# For typical corner:
# set_operating_conditions -library gf180mcu_fd_sc_mcu7t5v0__tt_025C_1v80

# For worst-case (slow):
# set_operating_conditions -library gf180mcu_fd_sc_mcu7t5v0__ss_n40C_1v62

#-----------------------------------------------------------------------------
# Power Constraints (optional)
#-----------------------------------------------------------------------------
# set_switching_activity -static_probability 0.5 -toggle_rate 0.1 [all_inputs]

#-----------------------------------------------------------------------------
# Design-Specific Constraints
#-----------------------------------------------------------------------------
# The FM output toggles at high frequency (up to clk/2)
# Ensure the output pad can handle the switching rate

# For high-frequency output, may need:
# set_driving_cell -lib_cell <high_drive_cell> [get_ports fm_out]

#-----------------------------------------------------------------------------
# Verification Constraints
#-----------------------------------------------------------------------------
# Check for unclocked registers
# report_unclocked_registers

# Check for combinational loops
# check_design -loops

#-----------------------------------------------------------------------------
# Notes for GF180MCU Integration
#-----------------------------------------------------------------------------
# 1. This design uses only standard cells (no SRAM/ROM macros)
# 2. The melody ROM will be synthesized to logic gates
# 3. For larger melodies, consider using SRAM macro
# 4. The 32-bit accumulator addition is timing-critical
# 5. Test at target frequency before tapeout
#
# Recommended synthesis flow:
#   1. Run synthesis with these constraints
#   2. Check timing reports for violations
#   3. Adjust CLK_PERIOD if needed
#   4. Run place & route
#   5. Verify timing closure post-route
#   6. Run LVS and DRC
