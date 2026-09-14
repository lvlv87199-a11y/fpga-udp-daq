`timescale 1ns/1ps

module packetizer_tb;

    localparam integer DATA_WIDTH = 16;
    localparam integer FIFO_DEPTH = 8;

    logic                    clk;
    logic                    rst_n;
    logic                    enable;
    logic [15:0]             samples_per_packet;

    logic                    fifo_wr_en;
    logic [DATA_WIDTH-1:0]   fifo_din;
    logic                    fifo_full;
    logic                    fifo_empty;
    logic                    fifo_rd_en;
    logic [DATA_WIDTH-1:0]   fifo_dout;
    logic                    fifo_overflow;

    logic                    payload_valid;
    logic                    payload_ready;
    logic [DATA_WIDTH-1:0]   payload_data;
    logic                    payload_last;
    logic                    checksum_valid;
    logic                    checksum_ready;
    logic [15:0]             checksum_data;
    logic                    packet_done;
    logic                    busy;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (fifo_wr_en),
        .din      (fifo_din),
        .full     (fifo_full),
        .rd_en    (fifo_rd_en),
        .dout     (fifo_dout),
        .empty    (fifo_empty),
        .overflow (fifo_overflow)
    );

    packetizer #(
        .DATA_WIDTH(DATA_WIDTH),
        .COUNT_WIDTH(16)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .enable              (enable),
        .samples_per_packet  (samples_per_packet),
        .fifo_empty          (fifo_empty),
        .fifo_rd_en          (fifo_rd_en),
        .fifo_dout           (fifo_dout),
        .payload_valid       (payload_valid),
        .payload_ready       (payload_ready),
        .payload_data        (payload_data),
        .payload_last        (payload_last),
        .checksum_valid      (checksum_valid),
        .checksum_ready      (checksum_ready),
        .checksum_data       (checksum_data),
        .packet_done         (packet_done),
        .busy                (busy)
    );

    always #5 clk = ~clk;

    task automatic fifo_write(input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            fifo_din   = value;
            fifo_wr_en = 1'b1;
            @(posedge clk);
            #1;
            fifo_wr_en = 1'b0;
        end
    endtask

    task automatic expect_checksum(input logic [15:0] expected_checksum);
        begin
            while (1) begin
                @(posedge clk);
                if (checksum_valid && checksum_ready) begin
                    if (checksum_data !== expected_checksum) begin
                        $fatal(1, "Checksum mismatch: expected 0x%04h, got 0x%04h",
                               expected_checksum, checksum_data);
                    end
                    disable expect_checksum;
                end
            end
        end
    endtask

    task automatic expect_payload(
        input logic [DATA_WIDTH-1:0] expected_data,
        input logic                  expected_last
    );
        begin
            while (1) begin
                @(posedge clk);
                if (payload_valid && payload_ready) begin
                    if (payload_data !== expected_data || payload_last !== expected_last) begin
                        $fatal(1, "Payload mismatch: expected data=0x%04h last=%b, got data=0x%04h last=%b",
                               expected_data, expected_last, payload_data, payload_last);
                    end
                    disable expect_payload;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("sim/packetizer_tb.vcd");
        $dumpvars(0, packetizer_tb);

        clk                 = 1'b0;
        rst_n               = 1'b0;
        enable              = 1'b0;
        samples_per_packet  = 16'd4;
        fifo_wr_en          = 1'b0;
        fifo_din            = '0;
        payload_ready       = 1'b0;
        checksum_ready      = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        @(negedge clk);
        rst_n  = 1'b1;
        enable = 1'b1;

        fifo_write(16'h1000);
        fifo_write(16'h1001);
        fifo_write(16'h1002);
        fifo_write(16'h1004);

        // Backpressure must hold the first payload sample stable.
        while (!payload_valid) @(negedge clk);
        if (payload_data !== 16'h1000 || payload_last !== 1'b0) begin
            $fatal(1, "First payload sample is incorrect");
        end
        repeat (2) begin
            @(negedge clk);
            if (!payload_valid || payload_data !== 16'h1000) begin
                $fatal(1, "Payload changed while ready was low");
            end
        end

        @(negedge clk);
        payload_ready = 1'b1;
        expect_payload(16'h1000, 1'b0);
        expect_payload(16'h1001, 1'b0);
        expect_payload(16'h1002, 1'b0);
        expect_payload(16'h1004, 1'b1);

        // The checksum is a separate valid/ready beat after the last sample.
        repeat (2) begin
            @(negedge clk);
            if (!checksum_valid || checksum_data !== 16'h0007) begin
                $fatal(1, "Checksum changed while ready was low");
            end
        end

        @(negedge clk);
        checksum_ready = 1'b1;
        expect_checksum(16'h0007);

        @(negedge clk);
        if (!packet_done || busy) begin
            $fatal(1, "Packet completion or busy state is incorrect");
        end

        $display("PASS: packetizer FSM, FIFO read latency and payload backpressure checks");
        $finish;
    end

endmodule
