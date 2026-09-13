`timescale 1ns/1ps

module sample_generator_tb;

    localparam integer DATA_WIDTH    = 16;
    localparam integer DIVIDER_WIDTH = 4;

    logic                     clk;
    logic                     rst_n;
    logic                     enable;
    logic [DIVIDER_WIDTH-1:0] sample_divider;
    logic                     sample_valid;
    logic                     sample_ready;
    logic [DATA_WIDTH-1:0]    sample_data;

    sample_generator #(
        .DATA_WIDTH(DATA_WIDTH),
        .DIVIDER_WIDTH(DIVIDER_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .sample_divider (sample_divider),
        .sample_valid   (sample_valid),
        .sample_ready   (sample_ready),
        .sample_data    (sample_data)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/sample_generator_tb.vcd");
        $dumpvars(0, sample_generator_tb);

        clk            = 1'b0;
        rst_n          = 1'b0;
        enable         = 1'b0;
        sample_divider = 4'd2;
        sample_ready   = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        if (sample_valid !== 1'b0) begin
            $fatal(1, "Reset should leave sample_valid low");
        end

        // Generate sample 0, then hold it while downstream applies backpressure.
        @(negedge clk);
        rst_n  = 1'b1;
        enable = 1'b1;
        @(posedge clk);
        #1;
        if (sample_valid !== 1'b1 || sample_data !== 16'h0000) begin
            $fatal(1, "First sample was not generated correctly");
        end

        repeat (2) begin
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b1 || sample_data !== 16'h0000) begin
                $fatal(1, "Sample changed while ready was low");
            end
        end

        // Accept sample 0 and verify two idle divider cycles before sample 1.
        @(negedge clk);
        sample_ready = 1'b1;
        @(posedge clk);
        #1;
        if (sample_valid !== 1'b0) begin
            $fatal(1, "Accepted sample should clear valid");
        end
        sample_ready = 1'b0;

        repeat (2) begin
            @(posedge clk);
            #1;
            if (sample_valid !== 1'b0) begin
                $fatal(1, "Divider did not insert an idle cycle");
            end
        end

        @(posedge clk);
        #1;
        if (sample_valid !== 1'b1 || sample_data !== 16'h0001) begin
            $fatal(1, "Second sample or divider timing is incorrect");
        end

        // Disabling generation must not withdraw an unaccepted valid sample.
        @(negedge clk);
        enable       = 1'b0;
        sample_ready = 1'b0;
        @(posedge clk);
        #1;
        if (sample_valid !== 1'b1 || sample_data !== 16'h0001) begin
            $fatal(1, "Pending valid sample was lost when enable went low");
        end

        @(negedge clk);
        sample_ready = 1'b1;
        @(posedge clk);
        #1;
        if (sample_valid !== 1'b0) begin
            $fatal(1, "Pending sample was not accepted");
        end

        // Re-enable and confirm the sequence continues with sample 2.
        @(negedge clk);
        enable = 1'b1;
        @(posedge clk);
        #1;
        if (sample_valid !== 1'b1 || sample_data !== 16'h0002) begin
            $fatal(1, "Sample sequence did not continue after re-enable");
        end

        @(posedge clk);
        #1;
        if (sample_valid !== 1'b0) begin
            $fatal(1, "Final sample was not accepted");
        end

        $display("PASS: sample_generator valid/ready/divider checks");
        $finish;
    end

endmodule
