import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


async def write_reg(dut, addr, value):
    await FallingEdge(dut.clk)
    dut.ctrl_addr.value = addr
    dut.ctrl_wdata.value = value
    dut.ctrl_wr_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.ctrl_wr_en.value = 0


@cocotb.test()
async def test_random_output_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.ctrl_wr_en.value = 0
    dut.ctrl_rd_en.value = 0
    dut.ctrl_addr.value = 0
    dut.ctrl_wdata.value = 0
    dut.checksum_error_event.value = 0
    dut.payload_ready.value = 0
    dut.checksum_ready.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.rst_n.value = 1
    await Timer(1, units="ns")

    await write_reg(dut, 0x04, 0)
    await write_reg(dut, 0x08, 8)
    await write_reg(dut, 0x00, 1)

    rng = random.Random(0xD17)
    received = []
    checksums = []
    packet_xor = 0
    packet_samples = 0
    completed_packets = 0
    max_fifo_level = 0
    payload_stalls = 0
    checksum_stalls = 0

    for cycle in range(5000):
        await FallingEdge(dut.clk)
        max_fifo_level = max(max_fifo_level, int(dut.fifo_level.value))

        payload_ready = rng.random() < 0.58
        checksum_ready = rng.random() < 0.67
        dut.payload_ready.value = int(payload_ready)
        dut.checksum_ready.value = int(checksum_ready)

        payload_valid = bool(int(dut.payload_valid.value))
        checksum_valid = bool(int(dut.checksum_valid.value))
        if payload_valid and not payload_ready:
            payload_stalls += 1
        if checksum_valid and not checksum_ready:
            checksum_stalls += 1

        if payload_valid and payload_ready:
            value = int(dut.payload_data.value)
            assert value == len(received), (
                f"sample loss/reorder at index {len(received)}: got {value}"
            )
            received.append(value)
            packet_xor ^= value
            packet_samples += 1
            assert int(dut.payload_last.value) == int(packet_samples == 8)

        if checksum_valid and checksum_ready:
            assert packet_samples == 8
            assert int(dut.checksum_data.value) == packet_xor
            checksums.append(packet_xor)
            packet_xor = 0
            packet_samples = 0

        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.packet_done.value):
            completed_packets += 1

        if len(received) >= 64 and completed_packets >= 8:
            break
    else:
        raise AssertionError("random backpressure test timed out")

    assert received == list(range(64))
    assert checksums == [0] * 8
    assert completed_packets == 8
    assert payload_stalls > 0
    assert checksum_stalls > 0
    assert 0 < max_fifo_level <= 8
    assert int(dut.fifo_overflow.value) == 0

    await write_reg(dut, 0x00, 0)
    dut._log.info(
        "PASS: random backpressure ordering; samples=%d packets=%d max_fifo_level=%d payload_stalls=%d checksum_stalls=%d",
        len(received),
        completed_packets,
        max_fifo_level,
        payload_stalls,
        checksum_stalls,
    )
