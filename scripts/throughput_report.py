"""Calculate DAQ sample bandwidth and per-frame protocol efficiency."""

from __future__ import annotations

import argparse
from dataclasses import dataclass


APPLICATION_HEADER_BYTES = 16
CHECKSUM_BYTES = 2
DEFAULT_FRAME_SAMPLES = (256, 512, 727, 736)
DEFAULT_SAMPLE_RATE = 1_000_000.0
DEFAULT_SAMPLE_WIDTH = 16
DEFAULT_WIRE_OVERHEAD = 14 + 20 + 8  # Ethernet II + IPv4 + UDP; no FCS/preamble/IPG.
DEFAULT_UDP_PAYLOAD_LIMIT = 1472


@dataclass(frozen=True)
class ThroughputRow:
    samples_per_frame: int
    payload_bytes: int
    application_frame_bytes: int
    wire_frame_bytes: int
    frames_per_second: float
    useful_bytes_per_second: float
    application_bytes_per_second: float
    wire_bytes_per_second: float
    overhead_bytes_per_frame: int
    efficiency: float
    fits_udp_payload: bool


def max_samples_per_frame(
    sample_width: int = DEFAULT_SAMPLE_WIDTH,
    udp_payload_limit: int = DEFAULT_UDP_PAYLOAD_LIMIT,
) -> int:
    """Return the largest whole-sample frame that fits in one UDP payload."""
    if sample_width <= 0 or sample_width % 8 != 0:
        raise ValueError("sample_width must be a positive multiple of 8")
    if udp_payload_limit <= 0:
        raise ValueError("udp_payload_limit must be positive")

    sample_bytes = sample_width // 8
    application_overhead = APPLICATION_HEADER_BYTES + CHECKSUM_BYTES
    available_payload = udp_payload_limit - application_overhead
    if available_payload < sample_bytes:
        return 0
    return available_payload // sample_bytes


def calculate_row(
    samples_per_frame: int,
    sample_rate: float = DEFAULT_SAMPLE_RATE,
    sample_width: int = DEFAULT_SAMPLE_WIDTH,
    wire_overhead: int = DEFAULT_WIRE_OVERHEAD,
    udp_payload_limit: int = DEFAULT_UDP_PAYLOAD_LIMIT,
) -> ThroughputRow:
    """Calculate one frame-size scenario."""
    if samples_per_frame <= 0:
        raise ValueError("samples_per_frame must be positive")
    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")
    if sample_width <= 0 or sample_width % 8 != 0:
        raise ValueError("sample_width must be a positive multiple of 8")
    if wire_overhead < 0:
        raise ValueError("wire_overhead cannot be negative")
    if udp_payload_limit <= 0:
        raise ValueError("udp_payload_limit must be positive")

    sample_bytes = sample_width // 8
    payload_bytes = samples_per_frame * sample_bytes
    application_overhead = APPLICATION_HEADER_BYTES + CHECKSUM_BYTES
    application_frame_bytes = payload_bytes + application_overhead
    wire_frame_bytes = application_frame_bytes + wire_overhead
    frames_per_second = sample_rate / samples_per_frame
    useful_bytes_per_second = sample_rate * sample_bytes
    application_bytes_per_second = application_frame_bytes * frames_per_second
    wire_bytes_per_second = wire_frame_bytes * frames_per_second

    return ThroughputRow(
        samples_per_frame=samples_per_frame,
        payload_bytes=payload_bytes,
        application_frame_bytes=application_frame_bytes,
        wire_frame_bytes=wire_frame_bytes,
        frames_per_second=frames_per_second,
        useful_bytes_per_second=useful_bytes_per_second,
        application_bytes_per_second=application_bytes_per_second,
        wire_bytes_per_second=wire_bytes_per_second,
        overhead_bytes_per_frame=application_overhead + wire_overhead,
        efficiency=useful_bytes_per_second / wire_bytes_per_second,
        fits_udp_payload=application_frame_bytes <= udp_payload_limit,
    )


def _mbits_per_second(bytes_per_second: float) -> float:
    return bytes_per_second * 8 / 1_000_000


def print_report(
    rows: list[ThroughputRow],
    sample_rate: float,
    sample_width: int,
    wire_overhead: int,
    udp_payload_limit: int,
) -> None:
    useful_mbps = _mbits_per_second(rows[0].useful_bytes_per_second)
    safe_samples = max_samples_per_frame(
        sample_width=sample_width,
        udp_payload_limit=udp_payload_limit,
    )
    print(f"sample rate: {sample_rate:g} samples/s, width: {sample_width} bit")
    print(
        f"wire overhead: {wire_overhead} bytes/frame; "
        f"UDP/IPv4 payload limit: {udp_payload_limit} bytes"
    )
    print(
        f"MTU-safe maximum: {safe_samples} samples/frame; "
        f"application frame <= {udp_payload_limit} bytes"
    )
    print(f"useful sample bandwidth: {useful_mbps:.3f} Mbit/s")
    print()
    print(
        "samples/frame  payload  app_frame  wire_frame  frames/s  "
        "overhead  useful_Mbit/s  wire_Mbit/s  efficiency  UDP_fit"
    )
    for row in rows:
        print(
            f"{row.samples_per_frame:13d}  "
            f"{row.payload_bytes:7d}  "
            f"{row.application_frame_bytes:9d}  "
            f"{row.wire_frame_bytes:10d}  "
            f"{row.frames_per_second:8.3f}  "
            f"{row.overhead_bytes_per_frame:8d}  "
            f"{_mbits_per_second(row.useful_bytes_per_second):13.3f}  "
            f"{_mbits_per_second(row.wire_bytes_per_second):11.3f}  "
            f"{row.efficiency * 100:9.3f}%  "
            f"{'yes' if row.fits_udp_payload else 'NO'}"
        )

    oversized = [row.samples_per_frame for row in rows if not row.fits_udp_payload]
    if oversized:
        print()
        print(
            "warning: application frames for "
            + ", ".join(map(str, oversized))
            + " samples/frame exceed the configured UDP payload limit."
        )
        print(f"recommendation: configure at most {safe_samples} samples/frame.")


def _self_test() -> None:
    rows = [calculate_row(count) for count in DEFAULT_FRAME_SAMPLES]
    assert rows[0].application_frame_bytes == 530
    assert rows[1].application_frame_bytes == 1042
    assert rows[2].application_frame_bytes == 1472
    assert rows[3].application_frame_bytes == 1490
    assert rows[0].wire_frame_bytes == 572
    assert rows[1].wire_frame_bytes == 1084
    assert rows[2].wire_frame_bytes == 1514
    assert rows[3].wire_frame_bytes == 1532
    assert rows[0].efficiency < rows[1].efficiency < rows[2].efficiency < rows[3].efficiency
    assert rows[0].fits_udp_payload
    assert rows[1].fits_udp_payload
    assert rows[2].fits_udp_payload
    assert not rows[3].fits_udp_payload
    assert max_samples_per_frame() == 727
    assert not calculate_row(728).fits_udp_payload
    print("PASS: throughput calculation self-test")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-rate", type=float, default=DEFAULT_SAMPLE_RATE)
    parser.add_argument("--sample-width", type=int, default=DEFAULT_SAMPLE_WIDTH)
    parser.add_argument(
        "--frame-samples",
        type=int,
        nargs="+",
        default=list(DEFAULT_FRAME_SAMPLES),
    )
    parser.add_argument("--wire-overhead", type=int, default=DEFAULT_WIRE_OVERHEAD)
    parser.add_argument(
        "--udp-payload-limit", type=int, default=DEFAULT_UDP_PAYLOAD_LIMIT
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    try:
        if args.self_test:
            _self_test()
            return 0
        rows = [
            calculate_row(
                samples_per_frame=count,
                sample_rate=args.sample_rate,
                sample_width=args.sample_width,
                wire_overhead=args.wire_overhead,
                udp_payload_limit=args.udp_payload_limit,
            )
            for count in args.frame_samples
        ]
    except ValueError as error:
        parser.error(str(error))

    print_report(
        rows,
        sample_rate=args.sample_rate,
        sample_width=args.sample_width,
        wire_overhead=args.wire_overhead,
        udp_payload_limit=args.udp_payload_limit,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
