module rv32_muldiv_unit (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [2:0]  op,
    output logic [31:0] y
);
    logic signed [63:0] ss_prod;
    logic        [63:0] uu_prod;
    logic        [31:0] a_mag;
    logic        [63:0] su_mag_prod;
    logic        [63:0] su_prod_bits;

    always_comb begin
        ss_prod = $signed(a) * $signed(b);
        uu_prod = $unsigned(a) * $unsigned(b);

        a_mag = a[31] ? (~a + 32'd1) : a;
        su_mag_prod = $unsigned(a_mag) * $unsigned(b);
        su_prod_bits = a[31] ? (~su_mag_prod + 64'd1) : su_mag_prod;

        unique case (op)
            3'b000: y = ss_prod[31:0];                         // MUL
            3'b001: y = ss_prod[63:32];                        // MULH
            3'b010: y = su_prod_bits[63:32];                   // MULHSU
            3'b011: y = uu_prod[63:32];                        // MULHU
            3'b100: begin                                       // DIV
                if (b == 32'd0) y = 32'hffff_ffff;
                else if (a == 32'h8000_0000 && b == 32'hffff_ffff)
                    y = 32'h8000_0000;
                else y = $signed(a) / $signed(b);
            end
            3'b101: y = (b == 32'd0) ? 32'hffff_ffff : ($unsigned(a) / $unsigned(b)); // DIVU
            3'b110: begin                                       // REM
                if (b == 32'd0) y = a;
                else if (a == 32'h8000_0000 && b == 32'hffff_ffff)
                    y = 32'd0;
                else y = $signed(a) % $signed(b);
            end
            3'b111: y = (b == 32'd0) ? a : ($unsigned(a) % $unsigned(b)); // REMU
            default: y = 32'd0;
        endcase
    end
endmodule
