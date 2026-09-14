import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


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
