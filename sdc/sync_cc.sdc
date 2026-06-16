# =========================================================================
# Synopsys Design Constraints (SDC) for sync_cc
# Description: This file defines constraints for the clock domain crossing
#              (CDC) paths and reset synchronization within the sync_cc module.
# =========================================================================

# -------------------------------------------------------------------------
# 1. Clock Domain Crossing (CDC) in sync_pulse_cdc
# -------------------------------------------------------------------------
# The toggle signal 'r_src_toggle' from the source clock domain is sampled
# by the first stage of the synchronizer register chain 'r_dst_sync[0]'
# in the destination clock domain. Since these clocks are asynchronous,
# we declare this path as a false path to disable normal setup/hold checks.
set_false_path -from [get_registers {*sync_pulse_cdc:*|r_src_toggle*}] -to [get_registers {*sync_pulse_cdc:*|r_dst_sync[0]*}]

# -------------------------------------------------------------------------
# 2. Reset Synchronizer (sync_reset_cdc) Asynchronous Input Paths
# -------------------------------------------------------------------------
# The global asynchronous reset (rst_n) assertions are asynchronous to
# all clock domains. The 'sync_reset_cdc' blocks are specifically designed
# to handle the asynchronous assertion and synchronize the deassertion.
# To prevent the timing analyzer from reporting false recovery/removal violations
# on the asynchronous clear/preset pins of the synchronizer shift registers,
# we apply a false path to these pins.
# (We search for both 'aclr' and 'clrn' pin names to support different Altera/Intel FPGA architectures).
set_false_path -to [get_pins -compatibility_mode -nocase {*sync_reset_cdc:*|r_rst_sync[*]|aclr}]
set_false_path -to [get_pins -compatibility_mode -nocase {*sync_reset_cdc:*|r_rst_sync[*]|clrn}]