#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build"

mkdir -p "$BUILD_DIR"
cd "$ROOT_DIR"

iverilog -g2012 \
    -s sync_fifo_tb \
    -o "$BUILD_DIR/sync_fifo_tb.vvp" \
    rtl/sync_fifo.sv \
    tb/sync_fifo_tb.sv

vvp "$BUILD_DIR/sync_fifo_tb.vvp"
