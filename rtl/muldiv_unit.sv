// One shared sign-extended multiplier covers MUL/MULH/MULHSU/MULHU.
// Combinational division remains available as a selectable baseline.
module rv32_muldiv_unit #(parameter ENABLE_DIV = 1) (
    input logic [31:0] a, b,
    input logic [2:0] op,
    output logic [31:0] y
);
    logic signed [32:0] mul_a, mul_b;
    logic signed [65:0] product;
    logic [31:0] div_result;
    assign mul_a = {(a[31] && (op == 3'b001 || op == 3'b010)), a};
    assign mul_b = {(b[31] && op == 3'b001), b};
    assign product = mul_a * mul_b;
    generate
        if (ENABLE_DIV) begin : g_comb_div
            always_comb begin
                case (op)
                    3'b100: begin
                        if (b == 0) div_result = 32'hffff_ffff;
                        else if (a == 32'h8000_0000 && b == 32'hffff_ffff)
                            div_result = 32'h8000_0000;
                        else div_result = $signed(a) / $signed(b);
                    end
                    3'b101: div_result = (b == 0) ? 32'hffff_ffff : (a / b);
                    3'b110: begin
                        if (b == 0) div_result = a;
                        else if (a == 32'h8000_0000 && b == 32'hffff_ffff)
                            div_result = 32'd0;
                        else div_result = $signed(a) % $signed(b);
                    end
                    3'b111: div_result = (b == 0) ? a : (a % b);
                    default: div_result = 0;
                endcase
            end
        end else begin : g_no_comb_div
            assign div_result = 0;
        end
    endgenerate
    assign y = op[2] ? div_result : (op == 0 ? product[31:0] : product[63:32]);
endmodule
