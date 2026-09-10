module rv32_branch_predictor #(
    parameter ENTRIES = 256
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] fetch_pc,
    output logic        predict_taken,
    output logic [31:0] predict_target,

    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_taken,
    input  logic [31:0] update_target
);
    localparam IDX_W = $clog2(ENTRIES);

    logic [1:0] bht [0:ENTRIES-1];
    logic       btb_valid [0:ENTRIES-1];
    logic [31:0] btb_tag [0:ENTRIES-1];
    logic [31:0] btb_target [0:ENTRIES-1];

    logic [IDX_W-1:0] fetch_idx, update_idx;
    integer i;

    assign fetch_idx  = fetch_pc[IDX_W+1:2];
    assign update_idx = update_pc[IDX_W+1:2];

    always_comb begin
        predict_taken  = 1'b0;
        predict_target = fetch_pc + 32'd4;
        if (btb_valid[fetch_idx] &&
            btb_tag[fetch_idx] == fetch_pc &&
            bht[fetch_idx][1]) begin
            predict_taken  = 1'b1;
            predict_target = btb_target[fetch_idx];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                bht[i]        <= 2'b01; // weakly not-taken
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= 32'd0;
                btb_target[i] <= 32'd0;
            end
        end else if (update_valid) begin
            btb_valid[update_idx]  <= 1'b1;
            btb_tag[update_idx]    <= update_pc;
            btb_target[update_idx] <= update_target;

            if (update_taken) begin
                if (bht[update_idx] != 2'b11)
                    bht[update_idx] <= bht[update_idx] + 2'b01;
            end else begin
                if (bht[update_idx] != 2'b00)
                    bht[update_idx] <= bht[update_idx] - 2'b01;
            end
        end
    end
endmodule
