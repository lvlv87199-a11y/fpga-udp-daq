#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build/cocotb_backpressure"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=daq_top \
MODULE=test_backpressure \
PYTHONPATH="$ROOT_DIR/tb" \
VERILOG_SOURCES="$ROOT_DIR/rtl/daq_ctrl.sv $ROOT_DIR/rtl/sample_generator.sv $ROOT_DIR/rtl/sync_fifo.sv $ROOT_DIR/rtl/packetizer.sv $ROOT_DIR/rtl/daq_top.sv" \
COMPILE_ARGS="-g2012 -Pdaq_top.FIFO_DEPTH=8" \
make -f "$(cocotb-config --makefiles)/Makefile.sim" clean

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=daq_top \
MODULE=test_backpressure \
PYTHONPATH="$ROOT_DIR/tb" \
VERILOG_SOURCES="$ROOT_DIR/rtl/daq_ctrl.sv $ROOT_DIR/rtl/sample_generator.sv $ROOT_DIR/rtl/sync_fifo.sv $ROOT_DIR/rtl/packetizer.sv $ROOT_DIR/rtl/daq_top.sv" \
COMPILE_ARGS="-g2012 -Pdaq_top.FIFO_DEPTH=8" \
make -f "$(cocotb-config --makefiles)/Makefile.sim"
