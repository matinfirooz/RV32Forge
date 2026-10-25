// Restoring division: one quotient bit per cycle. Requests are latched on
// start; changing input operands while busy cannot corrupt an operation.
module rv32_divider (
    input logic clk, rst_n, start,
    input logic [31:0] a, b,
    input logic signed_mode, remainder_mode,
    output logic busy, done,
    output logic [31:0] result
);
    logic [31:0] quotient, divisor;
    logic [32:0] remainder_reg;
    logic [5:0] count;
    logic negate_quotient, negate_remainder, want_remainder;
    logic [32:0] shifted_remainder, next_remainder;
    logic [31:0] next_quotient, magnitude_result;

    always_comb begin
        shifted_remainder = {remainder_reg[31:0], quotient[31]};
        next_quotient = {quotient[30:0], 1'b0};
        next_remainder = shifted_remainder;
        if (shifted_remainder >= {1'b0, divisor}) begin
            next_remainder = shifted_remainder - {1'b0, divisor};
            next_quotient[0] = 1'b1;
        end
        magnitude_result = want_remainder ? next_remainder[31:0] : next_quotient;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0; result <= 0;
            quotient <= 0; divisor <= 0; remainder_reg <= 0; count <= 0;
            negate_quotient <= 0; negate_remainder <= 0; want_remainder <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                if (b == 0) begin
                    result <= remainder_mode ? a : 32'hffff_ffff;
                    done <= 1;
                end else if (signed_mode && a == 32'h8000_0000 && b == 32'hffff_ffff) begin
                    result <= remainder_mode ? 32'd0 : 32'h8000_0000;
                    done <= 1;
                end else begin
                    quotient <= (signed_mode && a[31]) ? (~a + 32'd1) : a;
                    divisor <= (signed_mode && b[31]) ? (~b + 32'd1) : b;
                    remainder_reg <= 0; count <= 0;
                    negate_quotient <= signed_mode && (a[31] ^ b[31]);
                    negate_remainder <= signed_mode && a[31];
                    want_remainder <= remainder_mode;
                    busy <= 1;
                end
            end else if (busy) begin
                quotient <= next_quotient;
                remainder_reg <= next_remainder;
                count <= count + 6'd1;
                if (count == 6'd31) begin
                    result <= ((want_remainder && negate_remainder) ||
                               (!want_remainder && negate_quotient)) ?
                              (~magnitude_result + 32'd1) : magnitude_result;
                    busy <= 0; done <= 1;
                end
            end
        end
    end
endmodule
