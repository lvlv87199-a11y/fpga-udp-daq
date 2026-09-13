#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/sim/build"

mkdir -p "$BUILD_DIR"
cd "$ROOT_DIR"

iverilog -g2012 \
    -s sample_generator_tb \
    -o "$BUILD_DIR/sample_generator_tb.vvp" \
    rtl/sample_generator.sv \
    tb/sample_generator_tb.sv

vvp "$BUILD_DIR/sample_generator_tb.vvp"
