// Fixed-length FIFO payload packetizer.
//
// This version groups a configured number of FIFO samples into a payload
// stream. Frame headers, sequence numbers and checksums are intentionally
// left for the next day. The FSM accounts for the synchronous read latency
// of sync_fifo: READ_REQ -> READ_CAPTURE -> PAYLOAD.
module packetizer #(
    parameter integer DATA_WIDTH  = 16,
    parameter integer COUNT_WIDTH = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    enable,
    input  logic [COUNT_WIDTH-1:0]  samples_per_packet,

    input  logic                    fifo_empty,
    output logic                    fifo_rd_en,
    input  logic [DATA_WIDTH-1:0]   fifo_dout,

    output logic                    payload_valid,
    input  logic                    payload_ready,
    output logic [DATA_WIDTH-1:0]   payload_data,
    output logic                    payload_last,
    output logic                    packet_done,
    output logic                    busy
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_READ_REQ,
        ST_READ_CAPTURE,
        ST_PAYLOAD
    } state_t;

    state_t state;
    logic [COUNT_WIDTH-1:0] sample_index;
    logic [COUNT_WIDTH-1:0] packet_length;

    assign fifo_rd_en = (state == ST_READ_REQ) && enable && !fifo_empty;
    assign busy       = (state != ST_IDLE);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            sample_index  <= '0;
            packet_length <= '0;
            payload_valid <= 1'b0;
            payload_data  <= '0;
            payload_last  <= 1'b0;
            packet_done   <= 1'b0;
        end else begin
            packet_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    payload_valid <= 1'b0;
                    payload_last  <= 1'b0;

                    if (enable && (samples_per_packet != '0) && !fifo_empty) begin
                        packet_length <= samples_per_packet;
                        sample_index  <= '0;
                        state         <= ST_READ_REQ;
                    end
                end

                ST_READ_REQ: begin
                    // A disabled generator aborts before issuing another read.
                    // If the FIFO is empty, remain here until data arrives.
                    if (!enable) begin
                        state <= ST_IDLE;
                    end else if (!fifo_empty) begin
                        state <= ST_READ_CAPTURE;
                    end
                end

                ST_READ_CAPTURE: begin
                    // fifo_dout is valid here because the preceding state
                    // issued fifo_rd_en one clock earlier.
                    payload_data  <= fifo_dout;
                    payload_last  <= (sample_index == (packet_length - 1'b1));
                    payload_valid <= 1'b1;
                    state         <= ST_PAYLOAD;
                end

                ST_PAYLOAD: begin
                    if (payload_valid && payload_ready) begin
                        payload_valid <= 1'b0;

                        if (payload_last) begin
                            sample_index <= '0;
                            packet_done  <= 1'b1;
                            state        <= ST_IDLE;
                        end else begin
                            sample_index <= sample_index + 1'b1;
                            state        <= ST_READ_REQ;
                        end
                    end
                end

                default: begin
                    state         <= ST_IDLE;
                    payload_valid <= 1'b0;
                    payload_last  <= 1'b0;
                end
            endcase
        end
    end

endmodule
