`timescale 1ns/1ps
module tb_reset;
    logic clk=0,rst_n=0;
    wire halted;
    wire [31:0] cycle_count,instret_count,stall_count,branch_count,mispredict_count;
    rv32_soc #(.DMEM_BYTES(2048),.IMEM_HEX("")) dut(
        .clk(clk),.rst_n(rst_n),.halted(halted),.cycle_count(cycle_count),
        .instret_count(instret_count),.stall_count(stall_count),
        .branch_count(branch_count),.mispredict_count(mispredict_count));
    always #5 clk=~clk;
    integer t,stores;
    initial begin
        stores=0;
        repeat(3) @(negedge clk); rst_n=1;
        t=0;
        while(!dut.u_core.div_busy && t<40) begin @(negedge clk); t=t+1; end
        if(!dut.u_core.div_busy) $fatal(1,"divider did not start");
        repeat(5) @(negedge clk);
        rst_n=0; @(negedge clk);
        if(halted || dut.faulted || dut.u_core.div_busy || dut.u_core.div_done ||
           cycle_count!=0 || instret_count!=0 || dut.dmem_we || dut.commit_valid)
            $fatal(1,"core reset did not abort the in-flight operation");
        stores=0; rst_n=1; t=0;
        while(!halted && t<150) begin @(negedge clk); t=t+1; end
        if(!halted || dut.faulted) $fatal(1,"restart failed");
        if(stores!=2) $fatal(1,"unexpected stores after restart: %0d",stores);
        if({dut.dmem[263],dut.dmem[262],dut.dmem[261],dut.dmem[260]}!==32'd43631413)
            $fatal(1,"restart result corrupted");
        if(instret_count!=7) $fatal(1,"restart retirement count %0d",instret_count);
        $display("RESET PASS abort in-flight DIV, restart, no stale side effects"); $finish;
    end
    always @(posedge clk) if(rst_n && dut.dmem_we) stores=stores+1;
endmodule
