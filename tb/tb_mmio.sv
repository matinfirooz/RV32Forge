`timescale 1ns/1ps
module tb_mmio;
    logic clk=0,rst_n=0;
    wire halted;
    wire [31:0] cycle_count,instret_count,stall_count,branch_count,mispredict_count;
    rv32_soc #(.DMEM_BYTES(2048),.IMEM_HEX("programs/mmio.hex")) dut(.clk(clk),.rst_n(rst_n),.halted(halted),.cycle_count(cycle_count),
        .instret_count(instret_count),.stall_count(stall_count),
        .branch_count(branch_count),.mispredict_count(mispredict_count));
    always #5 clk=~clk;
    function automatic [31:0] word(input integer a);
        word={dut.dmem[a+3],dut.dmem[a+2],dut.dmem[a+1],dut.dmem[a]};
    endfunction
    integer cycles;
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        cycles=0;
        while(!halted && cycles<500) begin @(negedge clk); cycles=cycles+1; end
        if(!halted || dut.faulted) $fatal(1,"MMIO test failed to halt cleanly");
        if(word(256)==0 || word(256)>=cycle_count) $fatal(1,"cycle MMIO");
        if(word(260)==0 || word(260)>=instret_count) $fatal(1,"retirement MMIO");
        if(word(264)!=0) $fatal(1,"initial load stall counter");
        if(word(268)!=33) $fatal(1,"divide stall MMIO = %d",word(268));
        if(word(272)!=14) $fatal(1,"divide result");
        if(word(276)!=1) $fatal(1,"load-use stall MMIO = %d",word(276));
        if(word(280)<=word(256) || word(280)>=cycle_count) $fatal(1,"counter not read-only");
        if(word(284)!=1) $fatal(1,"MMIO byte-lane read = %d",word(284));
        if(word(288)<=256 || word(288)>=512) $fatal(1,"MMIO halfword read");
        if(word(292)!=130 || word(296)!=2) $fatal(1,"branch/mispredict MMIO");
        $display("MMIO PASS cycle/retirement/load-stall/div-stall/read-only counters"); $finish;
    end
endmodule
