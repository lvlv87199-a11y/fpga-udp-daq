// Top-level single-clock integration for the FPGA UDP DAQ simulation.
//
// The control block configures the sample generator and packetizer. Samples
// flow through the synchronous FIFO, while payload/checksum streams remain
// visible at the top level for a future UDP transport block.
module daq_top #(
    parameter integer DATA_WIDTH = 16,
    parameter integer FIFO_DEPTH = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  ctrl_wr_en,
    input  logic                  ctrl_rd_en,
    input  logic [7:0]            ctrl_addr,
    input  logic [31:0]           ctrl_wdata,
    output logic [31:0]           ctrl_rdata,
    output logic                  ctrl_rd_valid,
    input  logic                  checksum_error_event,

    output logic                  sample_valid,
    output logic                  fifo_full,
    output logic                  fifo_empty,
    output logic                  fifo_overflow,

    output logic                  payload_valid,
    input  logic                  payload_ready,
    output logic [DATA_WIDTH-1:0] payload_data,
    output logic                  payload_last,
    output logic                  checksum_valid,
    input  logic                  checksum_ready,
    output logic [15:0]           checksum_data,
    output logic                  packet_done,
    output logic                  busy
);

    logic                  ctrl_enable;
    logic [15:0]           ctrl_sample_divider;
    logic [15:0]           ctrl_samples_per_packet;
    logic                  sample_ready;
    logic [DATA_WIDTH-1:0] sample_data;
    logic                  fifo_wr_en;
    logic [DATA_WIDTH-1:0] fifo_dout;
    logic                  fifo_rd_en;

    // A full FIFO backpressures the generator. Therefore the normal top-level
    // data path never attempts a write that the FIFO would reject.
    assign sample_ready = !fifo_full;
    assign fifo_wr_en   = sample_valid && sample_ready;

    daq_ctrl ctrl_i (
        .clk                (clk),
        .rst_n              (rst_n),
        .wr_en              (ctrl_wr_en),
        .rd_en              (ctrl_rd_en),
        .addr               (ctrl_addr),
        .wdata              (ctrl_wdata),
        .rdata              (ctrl_rdata),
        .rd_valid           (ctrl_rd_valid),
        .enable             (ctrl_enable),
        .sample_divider     (ctrl_sample_divider),
        .samples_per_packet (ctrl_samples_per_packet),
        .fifo_full          (fifo_full),
        .fifo_overflow      (fifo_overflow),
        .sample_event       (fifo_wr_en),
        .frame_event        (packet_done),
        .checksum_error_event(checksum_error_event)
    );

    sample_generator #(
        .DATA_WIDTH    (DATA_WIDTH),
        .DIVIDER_WIDTH(16)
    ) sample_generator_i (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (ctrl_enable),
        .sample_divider (ctrl_sample_divider),
        .sample_valid   (sample_valid),
        .sample_ready   (sample_ready),
        .sample_data    (sample_data)
    );

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (FIFO_DEPTH)
    ) fifo_i (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (fifo_wr_en),
        .din      (sample_data),
        .full     (fifo_full),
        .rd_en    (fifo_rd_en),
        .dout     (fifo_dout),
        .empty    (fifo_empty),
        .overflow (fifo_overflow)
    );

    packetizer #(
        .DATA_WIDTH (DATA_WIDTH),
        .COUNT_WIDTH(16)
    ) packetizer_i (
        .clk                (clk),
        .rst_n              (rst_n),
        .enable             (ctrl_enable),
        .samples_per_packet(ctrl_samples_per_packet),
        .fifo_empty         (fifo_empty),
        .fifo_rd_en         (fifo_rd_en),
        .fifo_dout          (fifo_dout),
        .payload_valid      (payload_valid),
        .payload_ready      (payload_ready),
        .payload_data       (payload_data),
        .payload_last       (payload_last),
        .checksum_valid     (checksum_valid),
        .checksum_ready     (checksum_ready),
        .checksum_data      (checksum_data),
        .packet_done        (packet_done),
        .busy               (busy)
    );

endmodule
