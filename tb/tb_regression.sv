`timescale 1ns/1ps
module tb_regression;
    parameter ITERATIVE_DIV = 1;
    parameter ENABLE_BP = 1;
    parameter BP_ENTRIES = 64;
    logic clk=0, rst_n=0;
    wire halted, faulted, commit_valid, commit_mem_we, commit_stop, commit_fault;
    wire [31:0] cycle_count, instret_count, stall_count, branch_count, mispredict_count;
    wire [31:0] div_stall_count, fault_cause, fault_pc;
    wire [31:0] commit_pc, commit_instr, commit_wdata, commit_mem_addr, commit_mem_wdata, commit_cause;
    wire [4:0] commit_rd;
    wire [1:0] commit_mem_size;
    rv32_soc #(.ITERATIVE_DIV(ITERATIVE_DIV), .ENABLE_BP(ENABLE_BP), .BP_ENTRIES(BP_ENTRIES),
               .IMEM_WORDS(4096), .DMEM_BYTES(4096), .IMEM_HEX("")) dut (.*);
    always #5 clk=~clk;
    integer trace_fd, state_fd, limit, elapsed, retired, stores, committed_stores, committed_controls, i;
    string trace_path, state_path, wave_path;
    logic [31:0] saved_cycles, saved_instret;
    initial begin
        retired=0; stores=0; committed_stores=0; committed_controls=0;
        if (!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"TRACE plusarg required");
        if (!$value$plusargs("STATE=%s",state_path)) $fatal(1,"STATE plusarg required");
        if (!$value$plusargs("MAX_CYCLES=%d",limit)) limit=100000;
        trace_fd=$fopen(trace_path,"w");
        if (!trace_fd) $fatal(1,"cannot open trace file");
        if ($value$plusargs("VCD=%s",wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0,dut.u_core);
        end
        repeat(3) @(negedge clk);
        rst_n=1;
        elapsed=0;
        while (!halted && elapsed<limit) begin
            @(negedge clk); elapsed=elapsed+1;
        end
        if (!halted) $fatal(1,"TIMEOUT at fetch PC=%h",dut.imem_addr);
        if (instret_count !== retired) $fatal(1,"retirement counter mismatch: %d != %d",instret_count,retired);
        if (stores != committed_stores) $fatal(1,"duplicated/lost store: %d != %d",stores,committed_stores);
        if (branch_count !== committed_controls || mispredict_count>branch_count)
            $fatal(1,"branch/misprediction counter mismatch");
        state_fd=$fopen(state_path,"w");
        if (!state_fd) $fatal(1,"cannot open state file");
        for(i=0;i<32;i=i+1) $fdisplay(state_fd,"%08x",dut.u_core.u_rf.regs[i]);
        for(i=0;i<4096;i=i+4)
            $fdisplay(state_fd,"%08x",{dut.dmem[i+3],dut.dmem[i+2],dut.dmem[i+1],dut.dmem[i]});
        $fclose(state_fd); $fclose(trace_fd);
        saved_cycles=cycle_count; saved_instret=instret_count;
        repeat(3) begin
            @(negedge clk);
            if (dut.dmem_we || commit_valid || cycle_count!==saved_cycles || instret_count!==saved_instret)
                $fatal(1,"activity after halt");
        end
        $display("METRICS cycles=%0d instret=%0d load_stalls=%0d div_stalls=%0d branches=%0d mispredicts=%0d fault=%0d cause=%0d",
                 cycle_count,instret_count,stall_count,div_stall_count,branch_count,mispredict_count,faulted,fault_cause);
        $finish;
    end
    always @(posedge clk) begin
        if (rst_n && !halted) begin
            if (dut.u_core.u_rf.regs[0] !== 0) $fatal(1,"x0 changed");
            if (dut.dmem_we) stores=stores+1;
            if (commit_valid) begin
                if (!commit_stop) begin
                    retired=retired+1;
                    if (commit_instr[6:0]==7'h63 || commit_instr[6:0]==7'h6f || commit_instr[6:0]==7'h67)
                        committed_controls=committed_controls+1;
                end
                if (commit_mem_we) committed_stores=committed_stores+1;
                $fdisplay(trace_fd,"%08x %08x %02x %08x %01x %08x %08x %01x %01x %01x %08x",
                          commit_pc,commit_instr,commit_rd,commit_wdata,commit_mem_we,
                          commit_mem_addr,commit_mem_wdata,commit_mem_size,commit_stop,commit_fault,commit_cause);
            end
        end
    end
endmodule
