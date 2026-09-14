#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build"

mkdir -p "$BUILD_DIR"
cd "$ROOT_DIR"

iverilog -g2012 \
    -s daq_ctrl_tb \
    -o "$BUILD_DIR/daq_ctrl_tb.vvp" \
    rtl/daq_ctrl.sv \
    tb/daq_ctrl_tb.sv

vvp "$BUILD_DIR/daq_ctrl_tb.vvp"
