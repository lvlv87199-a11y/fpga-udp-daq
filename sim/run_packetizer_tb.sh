#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build"

mkdir -p "$BUILD_DIR"
cd "$ROOT_DIR"

iverilog -g2012 \
    -s packetizer_tb \
    -o "$BUILD_DIR/packetizer_tb.vvp" \
    rtl/sync_fifo.sv \
    rtl/packetizer.sv \
    tb/packetizer_tb.sv

vvp "$BUILD_DIR/packetizer_tb.vvp"
