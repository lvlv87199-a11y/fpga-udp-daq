#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build/cocotb_fifo"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=sync_fifo \
MODULE=test_sync_fifo \
PYTHONPATH="$ROOT_DIR/tb" \
VERILOG_SOURCES="$ROOT_DIR/rtl/sync_fifo.sv" \
COMPILE_ARGS="-g2012 -Psync_fifo.DATA_WIDTH=8 -Psync_fifo.DEPTH=4" \
make -f "$(cocotb-config --makefiles)/Makefile.sim" clean

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=sync_fifo \
MODULE=test_sync_fifo \
PYTHONPATH="$ROOT_DIR/tb" \
VERILOG_SOURCES="$ROOT_DIR/rtl/sync_fifo.sv" \
COMPILE_ARGS="-g2012 -Psync_fifo.DATA_WIDTH=8 -Psync_fifo.DEPTH=4" \
make -f "$(cocotb-config --makefiles)/Makefile.sim"
