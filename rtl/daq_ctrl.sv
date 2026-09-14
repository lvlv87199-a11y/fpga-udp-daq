// Simple memory-mapped control and status register block.
//
// The interface is intentionally smaller than AXI-Lite:
//   - wr_en/rd_en are one-cycle request pulses.
//   - addr is a byte address.
//   - writes update control outputs on the request clock edge.
//   - rd_valid pulses for one cycle with the registered read result.
module daq_ctrl #(
    parameter integer ADDR_WIDTH = 8,
    parameter integer DATA_WIDTH = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    wr_en,
    input  logic                    rd_en,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [DATA_WIDTH-1:0]   wdata,
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic                    rd_valid,

    output logic                    enable,
    output logic [15:0]             sample_divider,
    output logic [15:0]             samples_per_packet,
    input  logic                    fifo_full,
    input  logic                    fifo_overflow,
    input  logic                    sample_event,
    input  logic                    frame_event,
    input  logic                    checksum_error_event
);

    localparam logic [ADDR_WIDTH-1:0] ADDR_CONTROL            = 8'h00;
    localparam logic [ADDR_WIDTH-1:0] ADDR_SAMPLE_DIVIDER     = 8'h04;
    localparam logic [ADDR_WIDTH-1:0] ADDR_SAMPLES_PER_PACKET = 8'h08;
    localparam logic [ADDR_WIDTH-1:0] ADDR_STATUS              = 8'h0c;
    localparam logic [ADDR_WIDTH-1:0] ADDR_SAMPLE_COUNT        = 8'h10;
    localparam logic [ADDR_WIDTH-1:0] ADDR_FRAME_COUNT         = 8'h14;
    localparam logic [ADDR_WIDTH-1:0] ADDR_FIFO_OVERFLOW_COUNT = 8'h18;
    localparam logic [ADDR_WIDTH-1:0] ADDR_CHECKSUM_ERR_COUNT  = 8'h1c;

    logic [DATA_WIDTH-1:0] status_value;
    logic [31:0] sample_count;
    logic [31:0] frame_count;
    logic [31:0] fifo_overflow_count;
    logic [31:0] checksum_error_count;

    always_comb begin
        status_value    = '0;
        status_value[0] = enable;
        status_value[1] = fifo_full;
        status_value[2] = fifo_overflow;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rdata              <= '0;
            rd_valid           <= 1'b0;
            enable             <= 1'b0;
            sample_divider     <= 16'd0;
            samples_per_packet <= 16'd256;
            sample_count       <= 32'd0;
            frame_count        <= 32'd0;
            fifo_overflow_count <= 32'd0;
            checksum_error_count <= 32'd0;
        end else begin
            rd_valid <= rd_en;

            // Statistics are event counters. They intentionally wrap at
            // 32 bits; Day 16 does not add saturation or clear registers.
            if (sample_event) begin
                sample_count <= sample_count + 32'd1;
            end
            if (frame_event) begin
                frame_count <= frame_count + 32'd1;
            end
            if (fifo_overflow) begin
                fifo_overflow_count <= fifo_overflow_count + 32'd1;
            end
            if (checksum_error_event) begin
                checksum_error_count <= checksum_error_count + 32'd1;
            end

            if (wr_en) begin
                case (addr)
                    ADDR_CONTROL: begin
                        enable <= wdata[0];
                    end

                    ADDR_SAMPLE_DIVIDER: begin
                        sample_divider <= wdata[15:0];
                    end

                    ADDR_SAMPLES_PER_PACKET: begin
                        // Zero is rejected so the packetizer never receives
                        // an impossible packet length.
                        if (wdata[15:0] != 16'd0) begin
                            samples_per_packet <= wdata[15:0];
                        end
                    end

                    default: begin
                        // Unmapped writes have no side effect.
                    end
                endcase
            end

            if (rd_en) begin
                case (addr)
                    ADDR_CONTROL: begin
                        rdata <= {{(DATA_WIDTH-1){1'b0}}, enable};
                    end

                    ADDR_SAMPLE_DIVIDER: begin
                        rdata <= {{(DATA_WIDTH-16){1'b0}}, sample_divider};
                    end

                    ADDR_SAMPLES_PER_PACKET: begin
                        rdata <= {{(DATA_WIDTH-16){1'b0}}, samples_per_packet};
                    end

                    ADDR_STATUS: begin
                        rdata <= status_value;
                    end

                    ADDR_SAMPLE_COUNT: begin
                        rdata <= sample_count;
                    end

                    ADDR_FRAME_COUNT: begin
                        rdata <= frame_count;
                    end

                    ADDR_FIFO_OVERFLOW_COUNT: begin
                        rdata <= fifo_overflow_count;
                    end

                    ADDR_CHECKSUM_ERR_COUNT: begin
                        rdata <= checksum_error_count;
                    end

                    default: begin
                        rdata <= '0;
                    end
                endcase
            end
        end
    end

endmodule
