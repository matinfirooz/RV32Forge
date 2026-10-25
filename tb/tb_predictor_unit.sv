`timescale 1ns/1ps
module tb_predictor_unit;
    logic clk=0,rst_n=0,update_valid=0,update_taken=0;
    logic [31:0] fetch_pc=0,update_pc=0,update_target=0;
    wire predict_taken;
    wire [31:0] predict_target;
    rv32_branch_predictor #(.ENTRIES(4)) dut(.*);
    always #5 clk=~clk;
    task automatic train(input [31:0] pc,input taken,input [31:0] target);
        begin
            update_valid=1; update_pc=pc; update_taken=taken; update_target=target;
            @(negedge clk); update_valid=0; #1;
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst_n=1; #1;
        if(predict_taken || predict_target!=4) $fatal(1,"reset prediction");
        train(0,1,32'h40);
        if(!predict_taken || predict_target!=32'h40) $fatal(1,"cold taken training");
        train(0,1,32'h40); train(0,1,32'h40);
        if(dut.bht[0]!=3) $fatal(1,"taken saturation");
        train(0,0,32'h40); train(0,0,32'h40); train(0,0,32'h40); train(0,0,32'h40);
        if(predict_taken || dut.bht[0]!=0) $fatal(1,"not-taken saturation");
        train(32'h10,1,32'h80); // same index, different full tag
        if(predict_taken) $fatal(1,"false BTB alias hit");
        fetch_pc=32'h10; #1;
        if(!predict_taken || predict_target!=32'h80 || dut.bht[0]!=2)
            $fatal(1,"replacement history/target");
        train(32'h10,1,32'h84);
        if(predict_target!=32'h84) $fatal(1,"target update");
        rst_n=0; @(negedge clk); rst_n=1; #1;
        if(predict_taken) $fatal(1,"reset invalidation");
        $display("PREDICTOR UNIT PASS saturation, aliasing, replacement, target, reset"); $finish;
    end
endmodule
