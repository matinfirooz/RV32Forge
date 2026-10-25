module rv32_regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata,
    input  logic [4:0]  raddr1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2
);
    logic [31:0] regs [0:31];
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else begin
            if (we && (waddr != 5'd0))
                regs[waddr] <= wdata;
            regs[0] <= 32'd0;
        end
    end

    always_comb begin
        rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
        rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];
    end
endmodule
