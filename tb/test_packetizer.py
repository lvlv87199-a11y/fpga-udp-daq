from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from reference_packet import build_frame


class FifoDriver:
    """Drive the packetizer's FIFO-side interface with sync-read latency."""

    def __init__(self, dut, samples=()):
        self.dut = dut
        self.queue = deque(samples)
        self.pending_data = None

    def add(self, samples):
        self.queue.extend(samples)

    async def run(self):
        self.dut.fifo_dout.value = 0
        self.dut.fifo_empty.value = int(not self.queue)

        while True:
            await FallingEdge(self.dut.clk)
            # Keep fifo_empty at its pre-read value through the next rising edge.
            self.dut.fifo_empty.value = int(not self.queue)
            await Timer(1, units="ns")

            if int(self.dut.fifo_rd_en.value):
                assert self.queue, "packetizer requested a read from an empty model FIFO"
                self.pending_data = self.queue.popleft()

            await RisingEdge(self.dut.clk)
            if self.pending_data is not None:
                self.dut.fifo_dout.value = self.pending_data
                self.pending_data = None
            self.dut.fifo_empty.value = int(not self.queue)


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.samples_per_packet.value = 0
    dut.payload_ready.value = 0
    dut.checksum_ready.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.rst_n.value = 1
    await Timer(1, units="ns")


async def collect_payload(dut, sample_count, start_cycle=0):
    samples = []
    last_flags = []
    cycle = start_cycle

    while len(samples) < sample_count:
        await FallingEdge(dut.clk)
        ready = (cycle % 3) != 0
        dut.payload_ready.value = int(ready)

        valid = bool(int(dut.payload_valid.value))
        held_data = int(dut.payload_data.value) if valid and not ready else None
        held_last = int(dut.payload_last.value) if valid and not ready else None
        accepted_data = int(dut.payload_data.value) if valid and ready else None
        accepted_last = int(dut.payload_last.value) if valid and ready else None

        await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        if held_data is not None:
            assert int(dut.payload_valid.value) == 1
            assert int(dut.payload_data.value) == held_data
            assert int(dut.payload_last.value) == held_last

        if accepted_data is not None:
            samples.append(accepted_data)
            last_flags.append(accepted_last)
        cycle += 1

    return samples, last_flags, cycle


async def accept_checksum(dut, expected_checksum):
    stable_data = None
    for _ in range(2):
        await FallingEdge(dut.clk)
        dut.checksum_ready.value = 0
        assert int(dut.checksum_valid.value) == 1
        current_data = int(dut.checksum_data.value)
        if stable_data is None:
            stable_data = current_data
        assert current_data == stable_data
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")

    await FallingEdge(dut.clk)
    assert int(dut.checksum_valid.value) == 1
    assert int(dut.checksum_data.value) == expected_checksum
    dut.checksum_ready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.packet_done.value) == 1
    assert int(dut.busy.value) == 0
    assert int(dut.checksum_data.value) == expected_checksum
    dut.checksum_ready.value = 0


async def run_complete_packet(dut, expected_samples):
    dut.samples_per_packet.value = len(expected_samples)
    dut.enable.value = 1
    dut.payload_ready.value = 0
    dut.checksum_ready.value = 0

    received, last_flags, _ = await collect_payload(dut, len(expected_samples))
    assert received == expected_samples
    assert last_flags == [0] * (len(expected_samples) - 1) + [1]

    checksum = 0
    for sample in expected_samples:
        checksum ^= sample
    await accept_checksum(dut, checksum)

    dut.enable.value = 0
    dut.payload_ready.value = 0
    await Timer(1, units="ns")


@cocotb.test()
async def test_packetizer_coverage(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    fifo = FifoDriver(dut)
    cocotb.start_soon(fifo.run())
    await reset_dut(dut)

    # Frame sequence is part of the reference-model contract until RTL headers
    # are added to packetizer.
    frame_zero = build_frame([0x1000], frame_seq=0)
    frame_one = build_frame([0x1001], frame_seq=1)
    assert int.from_bytes(frame_zero[8:12], "big") == 0
    assert int.from_bytes(frame_one[8:12], "big") == 1

    cases = [
        [0x0101],
        [0x1000, 0x1001, 0x1002, 0x1003],
        [0x2000 + index for index in range(8)],
    ]
    for expected_samples in cases:
        fifo.add(expected_samples)
        dut.fifo_empty.value = 0
        await Timer(1, units="ns")
        await run_complete_packet(dut, expected_samples)

    dut._log.info(
        "PASS: packet lengths, payload order, frame-seq reference, checksum and backpressure"
    )


@cocotb.test()
async def test_packetizer_tail_waits_for_completion(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    fifo = FifoDriver(dut)
    cocotb.start_soon(fifo.run())
    await reset_dut(dut)

    fifo.add([0x3000, 0x3001])
    dut.fifo_empty.value = 0
    dut.samples_per_packet.value = 4
    dut.enable.value = 1
    dut.payload_ready.value = 1
    await Timer(1, units="ns")

    first_samples, first_last, cycle = await collect_payload(dut, 2, start_cycle=1)
    assert first_samples == [0x3000, 0x3001]
    assert first_last == [0, 0]

    # The packetizer must wait in the read-request state, not emit checksum or
    # packet_done for an incomplete fixed-length packet.
    for _ in range(4):
        await FallingEdge(dut.clk)
        dut.payload_ready.value = 1
        dut.checksum_ready.value = 0
        assert int(dut.payload_valid.value) == 0
        assert int(dut.checksum_valid.value) == 0
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        assert int(dut.packet_done.value) == 0
        assert int(dut.busy.value) == 1

    fifo.add([0x3002, 0x3003])
    dut.fifo_empty.value = 0
    await Timer(1, units="ns")
    remaining_samples, remaining_last, _ = await collect_payload(
        dut, 2, start_cycle=cycle
    )
    assert remaining_samples == [0x3002, 0x3003]
    assert remaining_last == [0, 1]
    await accept_checksum(dut, 0x0000)

    dut.enable.value = 0
    dut.payload_ready.value = 0
    dut._log.info("PASS: incomplete tail waits for remaining FIFO samples")
