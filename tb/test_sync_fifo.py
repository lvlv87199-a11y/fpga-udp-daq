import cocotb
import random
from collections import deque
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


DATA_WIDTH = 8
DEPTH = 4


async def write_item(dut, value):
    dut.din.value = value
    dut.wr_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.wr_en.value = 0
    dut.din.value = 0


async def read_item(dut, expected):
    dut.rd_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.dout.value) == expected, (
        f"FIFO data mismatch: expected 0x{expected:02x}, "
        f"got 0x{int(dut.dout.value):02x}"
    )
    dut.rd_en.value = 0


async def random_cycle(dut, model, write_enable, read_enable, value, stats):
    old_count = len(model)
    expected_read = model[0] if read_enable and old_count > 0 else None
    expected_overflow = write_enable and old_count == DEPTH

    dut.din.value = value
    dut.wr_en.value = int(write_enable)
    dut.rd_en.value = int(read_enable)
    await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    await ReadOnly()

    if expected_read is not None:
        assert int(dut.dout.value) == expected_read, (
            f"random FIFO mismatch: expected 0x{expected_read:02x}, "
            f"got 0x{int(dut.dout.value):02x}"
        )

    if read_enable and old_count == 0:
        stats["empty_read_attempts"] += 1
    if write_enable and old_count == DEPTH:
        stats["overflow_events"] += 1

    # Apply the same acceptance rules as sync_fifo, using the pre-edge state.
    if read_enable and old_count > 0:
        model.popleft()
        stats["accepted_reads"] += 1
    if write_enable and old_count < DEPTH:
        model.append(value)
        stats["accepted_writes"] += 1

    assert int(dut.overflow.value) == int(expected_overflow)
    assert int(dut.empty.value) == int(len(model) == 0)
    assert int(dut.full.value) == int(len(model) == DEPTH)
    await Timer(1, units="ns")


@cocotb.test()
async def test_sync_fifo(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.din.value = 0

    # Reset is synchronous and active-low.
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0
    assert int(dut.overflow.value) == 0

    dut.rst_n.value = 1

    # A read from an empty FIFO is ignored.
    dut.rd_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.rd_en.value = 0
    assert int(dut.empty.value) == 1
    assert int(dut.overflow.value) == 0

    # Fill the four-entry FIFO.
    for value in (0x11, 0x22, 0x33, 0x44):
        await write_item(dut, value)
    assert int(dut.full.value) == 1
    assert int(dut.empty.value) == 0

    # A write while full is rejected and creates a one-cycle overflow pulse.
    dut.din.value = 0xEE
    dut.wr_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.overflow.value) == 1
    assert int(dut.full.value) == 1
    dut.wr_en.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.overflow.value) == 0

    # Synchronous reads preserve FIFO order.
    for expected in (0x11, 0x22, 0x33, 0x44):
        await read_item(dut, expected)
    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0

    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0

    dut._log.info("PASS: cocotb sync_fifo reset/read/write/full/empty/overflow checks")


@cocotb.test()
async def test_sync_fifo_random(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.din.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    model = deque()
    stats = {
        "empty_read_attempts": 0,
        "overflow_events": 0,
        "accepted_reads": 0,
        "accepted_writes": 0,
    }

    # Directed boundary checks make the two required corner cases explicit.
    for _ in range(3):
        await random_cycle(dut, model, False, True, 0, stats)

    for value in (0x10, 0x11, 0x12, 0x13):
        await random_cycle(dut, model, True, False, value, stats)

    for _ in range(3):
        await random_cycle(dut, model, True, False, 0xEE, stats)

    while model:
        await random_cycle(dut, model, False, True, 0, stats)

    # Deterministic pseudo-random traffic with simultaneous read/write cases.
    rng = random.Random(0xDA12)
    next_value = 0x20
    for _ in range(2000):
        write_enable = rng.random() < 0.60
        read_enable = rng.random() < 0.55
        value = next_value & ((1 << DATA_WIDTH) - 1)
        next_value += 1
        await random_cycle(dut, model, write_enable, read_enable, value, stats)

    while model:
        await random_cycle(dut, model, False, True, 0, stats)

    assert stats["empty_read_attempts"] >= 3
    assert stats["overflow_events"] >= 3
    assert stats["accepted_reads"] > 500
    assert stats["accepted_writes"] > 500
    dut._log.info("PASS: cocotb randomized FIFO scoreboard checks: %s", stats)
