`timescale 1ns/1ps
module tb_divider;
    logic clk=0,rst_n=0,start=0,signed_mode=0,remainder_mode=0;
    logic [31:0] a=0,b=0;
    wire busy,done;
    wire [31:0] result;
    rv32_divider dut(.*);
    always #5 clk=~clk;
    integer fd,rc,n,cycles,sm,rm;
    logic [31:0] va,vb,expected;
    string path;
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        // Reset aborts an operation in flight and clears the completion pulse.
        a=123; b=7; start=1;
        @(negedge clk); start=0;
        repeat(4) @(negedge clk);
        rst_n=0; @(negedge clk);
        if (busy || done) $fatal(1,"reset did not cancel division");
        rst_n=1;
        if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"VECTORS required");
        fd=$fopen(path,"r"); if (!fd) $fatal(1,"vector file not found");
        n=0;
        while (!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %d %d %h\n",va,vb,sm,rm,expected);
            if (rc!=5) $fatal(1,"malformed vector");
            a=va; b=vb; signed_mode=(sm!=0); remainder_mode=(rm!=0); start=1;
            @(negedge clk); start=0; cycles=0;
            while (!done && cycles<34) begin
                // Alter inputs and try a new request while busy: neither is accepted.
                a=32'hdeadbeef; b=3; signed_mode=0; remainder_mode=0;
                start=busy;
                @(negedge clk); cycles=cycles+1;
            end
            start=0;
            if (!done || busy || result!==expected)
                $fatal(1,"DIV vector %0d a=%h b=%h s=%0d r=%0d expected=%h got=%h",n,va,vb,sm,rm,expected,result);
            if (vb!=0 && !(sm && va==32'h80000000 && vb==32'hffffffff) && cycles!=32)
                $fatal(1,"unexpected iterative latency %0d",cycles);
            @(negedge clk);
            if (done || busy) $fatal(1,"completion pulse not cleared");
            n=n+1;
        end
        $fclose(fd); $display("DIVIDER PASS vectors=%0d plus reset/handshake checks",n); $finish;
    end
endmodule
