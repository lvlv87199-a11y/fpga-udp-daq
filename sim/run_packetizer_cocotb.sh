#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build/cocotb_packetizer"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=packetizer \
MODULE=test_packetizer \
PYTHONPATH="$ROOT_DIR/tb:$ROOT_DIR/scripts" \
VERILOG_SOURCES="$ROOT_DIR/rtl/packetizer.sv" \
COMPILE_ARGS="-g2012" \
make -f "$(cocotb-config --makefiles)/Makefile.sim" clean

SIM=icarus \
TOPLEVEL_LANG=verilog \
TOPLEVEL=packetizer \
MODULE=test_packetizer \
PYTHONPATH="$ROOT_DIR/tb:$ROOT_DIR/scripts" \
VERILOG_SOURCES="$ROOT_DIR/rtl/packetizer.sv" \
COMPILE_ARGS="-g2012" \
make -f "$(cocotb-config --makefiles)/Makefile.sim"
