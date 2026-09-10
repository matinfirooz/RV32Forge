`timescale 1ns/1ps
module tb_rv32m;
    logic clk=0, rst_n=0, halted;
    logic [31:0] cycle_count, instret_count, stall_count, branch_count, mispredict_count;
    rv32_soc #(.IMEM_HEX("programs/rv32m_demo.hex")) dut (
        .clk(clk), .rst_n(rst_n), .halted(halted),
        .cycle_count(cycle_count), .instret_count(instret_count),
        .stall_count(stall_count), .branch_count(branch_count), .mispredict_count(mispredict_count)
    );
    always #5 clk=~clk;
    function automatic [31:0] word(input integer a);
        word={dut.dmem[a+3],dut.dmem[a+2],dut.dmem[a+1],dut.dmem[a]};
    endfunction
    integer t;
    initial begin
        repeat(4) @(posedge clk); rst_n<=1;
        t=0; while(!halted && t<400) begin @(posedge clk); t=t+1; end
        if(!halted) $fatal(1,"timeout");
        if(word('h180)!==32'd126)       $fatal(1,"MUL fail");
        if(word('h184)!==32'hffff_ffff) $fatal(1,"MULH fail");
        if(word('h188)!==32'hffff_ffff) $fatal(1,"MULHSU fail");
        if(word('h18c)!==32'd5)         $fatal(1,"MULHU fail");
        if(word('h190)!==32'd3)         $fatal(1,"DIV fail");
        if(word('h194)!==32'd715827881) $fatal(1,"DIVU fail");
        if(word('h198)!==32'hffff_ffff) $fatal(1,"REM fail");
        if(word('h19c)!==32'd3)         $fatal(1,"REMU fail");
        $display("RV32M complete extension PASS");
        $finish;
    end
endmodule
