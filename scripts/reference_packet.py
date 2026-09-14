"""Reference model for the DAQ UDP application frame.

The model intentionally covers only the application payload defined in
docs/packet_format.md. Ethernet, IP, and UDP headers are out of scope.
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path
from typing import Iterable


MAGIC = b"DAQ1"
VERSION = 1
HEADER_LENGTH = 16
MAX_SAMPLE_COUNT = 0xFFFF


def xor16(samples: Iterable[int]) -> int:
    """Return the v1 XOR16 checksum over 16-bit sample words."""
    checksum = 0
    for sample in samples:
        checksum ^= sample
    return checksum


def _validate_samples(samples: list[int]) -> None:
    if len(samples) > MAX_SAMPLE_COUNT:
        raise ValueError("sample count does not fit in the 16-bit header field")
    for index, sample in enumerate(samples):
        if not 0 <= sample <= 0xFFFF:
            raise ValueError(f"sample {index} is outside the unsigned 16-bit range")


def build_frame(samples: Iterable[int], frame_seq: int = 0, flags: int = 0) -> bytes:
    """Build one complete DAQ v1 application frame."""
    sample_list = list(samples)
    _validate_samples(sample_list)
    if not 0 <= frame_seq <= 0xFFFFFFFF:
        raise ValueError("frame_seq must fit in an unsigned 32-bit field")
    if not 0 <= flags <= 0xFF:
        raise ValueError("flags must fit in an unsigned 8-bit field")

    payload = b"".join(struct.pack(">H", sample) for sample in sample_list)
    header = struct.pack(
        ">4sBBHIHH",
        MAGIC,
        VERSION,
        flags,
        HEADER_LENGTH,
        frame_seq,
        len(sample_list),
        len(payload),
    )
    checksum = struct.pack(">H", xor16(sample_list))
    return header + payload + checksum


def parse_frame(frame: bytes) -> dict[str, object]:
    """Validate and decode a complete DAQ v1 application frame."""
    if len(frame) < HEADER_LENGTH + 2:
        raise ValueError("frame is shorter than the minimum DAQ v1 frame")

    magic, version, flags, header_length, frame_seq, sample_count, payload_length = (
        struct.unpack_from(">4sBBHIHH", frame, 0)
    )
    if magic != MAGIC:
        raise ValueError(f"unexpected magic: {magic!r}")
    if version != VERSION:
        raise ValueError(f"unsupported version: {version}")
    if header_length != HEADER_LENGTH:
        raise ValueError(f"unexpected header length: {header_length}")
    if payload_length != sample_count * 2:
        raise ValueError("payload length does not match sample count")

    expected_length = HEADER_LENGTH + payload_length + 2
    if len(frame) != expected_length:
        raise ValueError(
            f"frame length mismatch: expected {expected_length}, got {len(frame)}"
        )

    payload = frame[HEADER_LENGTH : HEADER_LENGTH + payload_length]
    received_checksum = struct.unpack_from(">H", frame, HEADER_LENGTH + payload_length)[0]
    samples = tuple(
        struct.unpack_from(">H", payload, offset)[0]
        for offset in range(0, payload_length, 2)
    )
    calculated_checksum = xor16(samples)
    if received_checksum != calculated_checksum:
        raise ValueError(
            f"checksum mismatch: expected 0x{calculated_checksum:04x}, "
            f"got 0x{received_checksum:04x}"
        )

    return {
        "flags": flags,
        "frame_seq": frame_seq,
        "sample_count": sample_count,
        "payload_length": payload_length,
        "samples": samples,
        "checksum": received_checksum,
    }


def _parse_integer(token: str) -> int:
    try:
        return int(token, 0)
    except ValueError:
        return int(token, 10)


def _read_samples(sample_tokens: list[str], input_path: Path | None) -> list[int]:
    if input_path is not None:
        text = input_path.read_text(encoding="utf-8")
        tokens = [token for token in re.split(r"[\s,]+", text) if token]
    elif sample_tokens:
        tokens = sample_tokens
    else:
        text = sys.stdin.read()
        tokens = [token for token in re.split(r"[\s,]+", text) if token]

    if not tokens:
        raise ValueError("no samples supplied")
    return [_parse_integer(token) for token in tokens]


def _self_test() -> None:
    frame = build_frame([0x1234, 0xABCD], frame_seq=7)
    expected = bytes.fromhex("444151310100001000000007000200041234abcdb9f9")
    assert frame == expected, frame.hex()
    decoded = parse_frame(frame)
    assert decoded["samples"] == (0x1234, 0xABCD)
    assert decoded["checksum"] == 0xB9F9
    print("PASS: reference packet build/parse/checksum self-test")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("samples", nargs="*", help="samples, decimal or 0x-prefixed")
    parser.add_argument("--input", type=Path, help="text file containing samples")
    parser.add_argument("--frame-seq", type=_parse_integer, default=0)
    parser.add_argument("--flags", type=_parse_integer, default=0)
    parser.add_argument("--output", type=Path, help="write binary frame to this file")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    try:
        if args.self_test:
            _self_test()
            return 0
        samples = _read_samples(args.samples, args.input)
        frame = build_frame(samples, frame_seq=args.frame_seq, flags=args.flags)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    if args.output is not None:
        args.output.write_bytes(frame)
        print(f"wrote {len(frame)} bytes to {args.output}")
    else:
        print(frame.hex())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
