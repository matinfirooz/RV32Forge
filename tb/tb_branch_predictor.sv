`timescale 1ns/1ps
module tb_branch_predictor;
    logic clk=0, rst_n=0, halted;
    logic [31:0] cycle_count, instret_count, stall_count, branch_count, mispredict_count;
    rv32_soc #(.IMEM_HEX("programs/branch_bench.hex")) dut (
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
        t=0; while(!halted && t<500) begin @(posedge clk); t=t+1; end
        if(!halted) $fatal(1,"timeout");
        if(word('h1c0)!==32'd820) $fatal(1,"loop result fail");
        if(branch_count < 32'd39) $fatal(1,"branch counter fail");
        if(mispredict_count >= branch_count) $fatal(1,"predictor did not learn");
        $display("Branch predictor PASS: branches=%0d mispredicts=%0d cycles=%0d",
                 branch_count,mispredict_count,cycle_count);
        $finish;
    end
endmodule
