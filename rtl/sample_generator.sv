// Configurable incrementing sample generator with a valid/ready interface.
//
// sample_divider is the number of idle clock cycles inserted after a
// successful transfer. A value of zero requests the shortest possible gap
// supported by this registered interface. sample_valid and sample_data stay
// stable while sample_ready is low.
module sample_generator #(
    parameter integer DATA_WIDTH    = 16,
    parameter integer DIVIDER_WIDTH = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  enable,
    input  logic [DIVIDER_WIDTH-1:0] sample_divider,
    output logic                  sample_valid,
    input  logic                  sample_ready,
    output logic [DATA_WIDTH-1:0] sample_data
);

    logic [DATA_WIDTH-1:0] next_sample;
    logic [DIVIDER_WIDTH-1:0] divider_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            next_sample   <= '0;
            divider_count <= '0;
            sample_valid  <= 1'b0;
            sample_data   <= '0;
        end else if (sample_valid) begin
            // Once valid is asserted, keep the sample pending until accepted.
            if (sample_ready) begin
                sample_valid  <= 1'b0;
                next_sample   <= next_sample + 1'b1;
                divider_count <= enable ? sample_divider : '0;
            end
        end else if (!enable) begin
            // Disable stops new samples without disturbing the sample sequence.
            divider_count <= '0;
        end else if (divider_count != '0) begin
            divider_count <= divider_count - 1'b1;
        end else begin
            sample_data  <= next_sample;
            sample_valid <= 1'b1;
        end
    end

endmodule
