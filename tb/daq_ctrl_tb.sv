`timescale 1ns/1ps

module daq_ctrl_tb;

    logic        clk;
    logic        rst_n;
    logic        wr_en;
    logic        rd_en;
    logic [7:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        rd_valid;
    logic        sample_event;
    logic        frame_event;
    logic        checksum_error_event;
    logic        enable;
    logic [15:0] sample_divider;
    logic [15:0] samples_per_packet;
    logic        fifo_full;
    logic        fifo_overflow;

    daq_ctrl dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .wr_en              (wr_en),
        .rd_en              (rd_en),
        .addr               (addr),
        .wdata              (wdata),
        .rdata              (rdata),
        .rd_valid           (rd_valid),
        .enable             (enable),
        .sample_divider     (sample_divider),
        .samples_per_packet (samples_per_packet),
        .fifo_full          (fifo_full),
        .fifo_overflow      (fifo_overflow),
        .sample_event       (sample_event),
        .frame_event        (frame_event),
        .checksum_error_event(checksum_error_event)
    );

    always #5 clk = ~clk;

    task automatic write_reg(input logic [7:0] wr_addr, input logic [31:0] value);
        begin
            @(negedge clk);
            addr  = wr_addr;
            wdata = value;
            wr_en = 1'b1;
            @(posedge clk);
            #1;
            wr_en = 1'b0;
        end
    endtask

    task automatic read_reg(input logic [7:0] rd_addr, input logic [31:0] expected);
        begin
            @(negedge clk);
            addr  = rd_addr;
            rd_en = 1'b1;
            @(posedge clk);
            #1;
            rd_en = 1'b0;
            if (rd_valid !== 1'b1 || rdata !== expected) begin
                $fatal(1, "Read mismatch at 0x%02h: expected 0x%08h, got 0x%08h (valid=%b)",
                       rd_addr, expected, rdata, rd_valid);
            end
        end
    endtask

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        wr_en         = 1'b0;
        rd_en         = 1'b0;
        addr          = '0;
        wdata         = '0;
        fifo_full     = 1'b0;
        fifo_overflow = 1'b0;
        sample_event  = 1'b0;
        frame_event   = 1'b0;
        checksum_error_event = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        if (enable !== 1'b0 || sample_divider !== 16'd0 ||
            samples_per_packet !== 16'd256 || rd_valid !== 1'b0) begin
            $fatal(1, "Reset defaults are invalid");
        end

        @(negedge clk);
        rst_n = 1'b1;

        write_reg(8'h00, 32'h1);
        write_reg(8'h04, 32'd7);
        write_reg(8'h08, 32'd512);

        if (enable !== 1'b1 || sample_divider !== 16'd7 ||
            samples_per_packet !== 16'd512) begin
            $fatal(1, "Control writes did not update outputs");
        end

        read_reg(8'h00, 32'h1);
        read_reg(8'h04, 32'd7);
        read_reg(8'h08, 32'd512);
        read_reg(8'h10, 32'd0);
        read_reg(8'h14, 32'd0);
        read_reg(8'h18, 32'd0);
        read_reg(8'h1c, 32'd0);

        fifo_full     = 1'b1;
        fifo_overflow = 1'b1;
        read_reg(8'h0c, 32'h7);
        fifo_full     = 1'b0;
        fifo_overflow = 1'b0;

        // One event of each type must increment the corresponding counter.
        @(negedge clk);
        sample_event         = 1'b1;
        frame_event          = 1'b1;
        checksum_error_event = 1'b1;
        @(posedge clk);
        #1;
        sample_event         = 1'b0;
        frame_event          = 1'b0;
        checksum_error_event = 1'b0;

        read_reg(8'h10, 32'd1);
        read_reg(8'h14, 32'd1);
        read_reg(8'h18, 32'd1);
        read_reg(8'h1c, 32'd1);

        // A zero packet length must be ignored.
        write_reg(8'h08, 32'd0);
        if (samples_per_packet !== 16'd512) begin
            $fatal(1, "Zero packet length was not rejected");
        end

        // A 16-bit DAQ frame has 18 bytes of application overhead. Keep the
        // complete application frame within the 1472-byte UDP payload.
        write_reg(8'h08, 32'd727);
        if (samples_per_packet !== 16'd727) begin
            $fatal(1, "MTU-safe maximum packet length was not accepted");
        end
        write_reg(8'h08, 32'd728);
        if (samples_per_packet !== 16'd727) begin
            $fatal(1, "Oversized packet length was not rejected");
        end

        read_reg(8'hfc, 32'd0);

        $display("PASS: daq_ctrl register read/write/status checks");
        $finish;
    end

endmodule
