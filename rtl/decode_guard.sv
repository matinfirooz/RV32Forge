// Reject reserved encodings instead of silently treating them as arithmetic.
// Privileged instructions and CSRs are intentionally outside this core's scope.
module rv32_decode_guard (
    input logic [31:0] instr,
    output logic illegal,
    output logic ebreak
);
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    always_comb begin
        illegal = 0;
        ebreak = (instr == 32'h0010_0073);
        case (opcode)
            7'h33: illegal = !((funct7 == 0) || (funct7 == 1) ||
                        (funct7 == 7'h20 && (funct3 == 0 || funct3 == 5)));
            7'h13: begin
                if (funct3 == 1) illegal = (funct7 != 0);
                if (funct3 == 5) illegal = !(funct7 == 0 || funct7 == 7'h20);
            end
            7'h03: illegal = !(funct3 == 0 || funct3 == 1 || funct3 == 2 ||
                              funct3 == 4 || funct3 == 5);
            7'h23: illegal = !(funct3 == 0 || funct3 == 1 || funct3 == 2);
            7'h63: illegal = (funct3 == 2 || funct3 == 3);
            7'h67: illegal = (funct3 != 0);
            7'h37, 7'h17, 7'h6f: illegal = 0;
            7'h0f: illegal = (funct3 != 0); // FENCE is a no-op on this ordered bus
            7'h73: illegal = !(instr == 32'h0000_0073 || ebreak);
            default: illegal = 1;
        endcase
    end
endmodule
