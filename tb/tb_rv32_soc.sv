`timescale 1ns/1ps

module tb_rv32_soc;
    logic clk = 0;
    logic rst_n = 0;
    logic halted;
    logic [31:0] cycle_count, instret_count, stall_count, branch_count, mispredict_count;

    rv32_soc #(.IMEM_HEX("programs/demo.hex")) dut (
        .clk(clk), .rst_n(rst_n), .halted(halted),
        .cycle_count(cycle_count), .instret_count(instret_count),
        .stall_count(stall_count), .branch_count(branch_count),
        .mispredict_count(mispredict_count)
    );

    always #5 clk = ~clk;

    function automatic [31:0] load_word(input integer addr);
        load_word = {dut.dmem[addr+3], dut.dmem[addr+2], dut.dmem[addr+1], dut.dmem[addr+0]};
    endfunction

    integer timeout;
    initial begin
        $dumpfile("rv32forge.vcd");
        $dumpvars(0, tb_rv32_soc);
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;

        timeout = 0;
        while (!halted && timeout < 500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!halted) $fatal(1, "TIMEOUT");

        if (load_word('h100) !== 32'd55)  $fatal(1, "bad 0x100");
        if (load_word('h104) !== 32'd110) $fatal(1, "bad 0x104");
        if (load_word('h108) !== 32'd1)   $fatal(1, "bad 0x108");
        if (load_word('h10c) !== 32'd165) $fatal(1, "bad 0x10c");

        $display("RV32Forge-Pro base pipeline PASS");
        $display("cycles=%0d instret=%0d stalls=%0d branches=%0d mispredicts=%0d",
                 cycle_count, instret_count, stall_count, branch_count, mispredict_count);
        $finish;
    end
endmodule
