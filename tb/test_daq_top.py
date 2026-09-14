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


async def read_reg(dut, addr, expected=None):
    await FallingEdge(dut.clk)
    dut.ctrl_addr.value = addr
    dut.ctrl_rd_en.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.ctrl_rd_en.value = 0
    assert int(dut.ctrl_rd_valid.value) == 1
    value = int(dut.ctrl_rdata.value)
    if expected is not None:
        assert value == expected
    return value


async def pulse_checksum_error(dut):
    await FallingEdge(dut.clk)
    dut.checksum_error_event.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.checksum_error_event.value = 0


@cocotb.test()
async def test_daq_top_controlled_data_path(dut):
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

    await read_reg(dut, 0x00, 0)
    await read_reg(dut, 0x08, 256)

    # Configure the real top-level path through daq_ctrl.
    await write_reg(dut, 0x04, 0)
    await write_reg(dut, 0x08, 4)
    await write_reg(dut, 0x00, 1)
    await read_reg(dut, 0x00, 1)
    await read_reg(dut, 0x08, 4)

    received = []
    last_flags = []
    checksums = []
    completed_packets = 0
    cycle = 0

    while completed_packets < 2:
        await FallingEdge(dut.clk)
        payload_ready = (cycle % 4) != 0
        dut.payload_ready.value = int(payload_ready)
        dut.checksum_ready.value = 1

        payload_valid = bool(int(dut.payload_valid.value))
        if payload_valid and payload_ready:
            received.append(int(dut.payload_data.value))
            last_flags.append(int(dut.payload_last.value))

        if int(dut.checksum_valid.value):
            checksums.append(int(dut.checksum_data.value))

        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.packet_done.value):
            completed_packets += 1
        cycle += 1

        assert cycle < 500, "top-level data path did not produce two packets"

    assert received == list(range(8))
    assert last_flags == [0, 0, 0, 1, 0, 0, 0, 1]
    assert checksums[:2] == [0, 0]

    # Disable generation through the control register and confirm status.
    await write_reg(dut, 0x00, 0)
    await read_reg(dut, 0x00, 0)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.busy.value) == 0

    generated_samples = await read_reg(dut, 0x10)
    sent_frames = await read_reg(dut, 0x14)
    fifo_overflows = await read_reg(dut, 0x18)
    assert generated_samples >= 8
    assert sent_frames >= 2
    assert fifo_overflows == 0

    await pulse_checksum_error(dut)
    checksum_errors = await read_reg(dut, 0x1C)
    assert checksum_errors == 1
    dut._log.info(
        "PASS: daq_top path and statistics: samples=%d frames=%d fifo_overflows=%d checksum_errors=%d",
        generated_samples,
        sent_frames,
        fifo_overflows,
        checksum_errors,
    )
