// Single-clock, synchronous FIFO.
//
// Reset is synchronous and active-low. A rejected write while the FIFO is
// full produces a one-cycle overflow pulse. Reads are synchronous: dout is
// updated on the clock edge that accepts a read request.
module sync_fifo #(
    parameter integer DATA_WIDTH = 16,
    parameter integer DEPTH      = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic                  full,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] dout,
    output logic                  empty,
    output logic                  overflow
);

    localparam integer PTR_WIDTH   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);
    localparam logic [PTR_WIDTH-1:0] PTR_LAST = PTR_WIDTH'(DEPTH - 1);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [COUNT_WIDTH-1:0] count;
    logic do_read;
    logic do_write;

    assign empty    = (count == '0);
    assign full     = (count == DEPTH_COUNT);
    assign do_read  = rd_en && !empty;
    assign do_write = wr_en && !full;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr   <= '0;
            wr_ptr   <= '0;
            count    <= '0;
            dout     <= '0;
            overflow <= 1'b0;
        end else begin
            // An attempted write while full is rejected and reported for one cycle.
            overflow <= wr_en && full;

            if (do_write) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == PTR_LAST) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (do_read) begin
                dout <= mem[rd_ptr];
                if (rd_ptr == PTR_LAST) begin
                    rd_ptr <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end

endmodule
