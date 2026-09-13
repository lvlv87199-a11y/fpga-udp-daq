`timescale 1ns/1ps

module sync_fifo_tb;

    localparam integer DATA_WIDTH = 8;
    localparam integer DEPTH      = 4;

    logic                  clk;
    logic                  rst_n;
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] din;
    logic                  full;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] dout;
    logic                  empty;
    logic                  overflow;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .din      (din),
        .full     (full),
        .rd_en    (rd_en),
        .dout     (dout),
        .empty    (empty),
        .overflow (overflow)
    );

    always #5 clk = ~clk;

    task automatic write_item(input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            din   = value;
            wr_en = 1'b1;
            @(posedge clk);
            #1;
            wr_en = 1'b0;
            din   = '0;
        end
    endtask

    task automatic read_item(input logic [DATA_WIDTH-1:0] expected);
        begin
            @(negedge clk);
            rd_en = 1'b1;
            @(posedge clk);
            #1;
            if (dout !== expected) begin
                $fatal(1, "FIFO data mismatch: expected 0x%0h, got 0x%0h",
                       expected, dout);
            end
            rd_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("sim/sync_fifo_tb.vcd");
        $dumpvars(0, sync_fifo_tb);

        clk   = 1'b0;
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = '0;

        // Synchronous reset: two clock edges establish the empty state.
        repeat (2) @(posedge clk);
        #1;
        if (empty !== 1'b1 || full !== 1'b0 || overflow !== 1'b0) begin
            $fatal(1, "Reset state is invalid");
        end

        // An empty read is ignored and does not create an overflow event.
        @(negedge clk);
        rst_n = 1'b1;
        rd_en = 1'b1;
        @(posedge clk);
        #1;
        rd_en = 1'b0;
        if (empty !== 1'b1 || overflow !== 1'b0) begin
            $fatal(1, "Empty-read behavior is invalid");
        end

        // Fill the FIFO and verify the full flag.
        write_item(8'h11);
        write_item(8'h22);
        write_item(8'h33);
        write_item(8'h44);
        if (full !== 1'b1 || empty !== 1'b0) begin
            $fatal(1, "Full-state behavior is invalid");
        end

        // A write while full is rejected and reported for one cycle.
        @(negedge clk);
        din   = 8'hee;
        wr_en = 1'b1;
        @(posedge clk);
        #1;
        if (overflow !== 1'b1 || full !== 1'b1) begin
            $fatal(1, "Overflow behavior is invalid");
        end
        wr_en = 1'b0;
        @(posedge clk);
        #1;
        if (overflow !== 1'b0) begin
            $fatal(1, "Overflow is not a one-cycle pulse");
        end

        // FIFO must preserve order and become empty after the last read.
        read_item(8'h11);
        read_item(8'h22);
        read_item(8'h33);
        read_item(8'h44);
        if (empty !== 1'b1 || full !== 1'b0) begin
            $fatal(1, "Final empty-state behavior is invalid");
        end

        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        if (empty !== 1'b1 || full !== 1'b0) begin
            $fatal(1, "Reset recovery is invalid");
        end

        $display("PASS: sync_fifo write/read/full/empty/overflow checks");
        $finish;
    end

endmodule
