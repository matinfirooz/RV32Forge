`timescale 1ns/1ps
module tb_muldiv_unit;
    logic [31:0] a,b;
    logic [2:0] op;
    wire [31:0] y;
    rv32_muldiv_unit dut(.*);
    integer fd,rc,n,operation;
    logic [31:0] expected;
    string path;
    initial begin
        if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"VECTORS required");
        fd=$fopen(path,"r"); if (!fd) $fatal(1,"vector file not found"); n=0;
        while (!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %d %h\n",a,b,operation,expected);
            if (rc!=4) $fatal(1,"malformed vector");
            op=operation[2:0]; #1;
            if (y!==expected) $fatal(1,"M vector %0d op=%0d a=%h b=%h expected=%h got=%h",n,op,a,b,expected,y);
            n=n+1;
        end
        $fclose(fd); $display("MULDIV PASS vectors=%0d",n); $finish;
    end
endmodule
