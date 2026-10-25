module rv32_soc #(
    parameter ITERATIVE_DIV = 1,
    parameter ENABLE_BP = 1,
    parameter BP_ENTRIES = 256,
    parameter IMEM_WORDS = 2048,
    parameter DMEM_BYTES = 65536,
    parameter IMEM_HEX   = "programs/demo.hex"
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic        halted,
    output logic [31:0] cycle_count,
    output logic [31:0] instret_count,
    output logic [31:0] stall_count,
    output logic [31:0] branch_count,
    output logic [31:0] mispredict_count,
    output logic [31:0] div_stall_count,
    output logic faulted,
    output logic [31:0] fault_cause, fault_pc,
    output logic commit_valid,
    output logic [31:0] commit_pc, commit_instr,
    output logic [4:0] commit_rd,
    output logic [31:0] commit_wdata,
    output logic commit_mem_we,
    output logic [31:0] commit_mem_addr, commit_mem_wdata,
    output logic [1:0] commit_mem_size,
    output logic commit_stop, commit_fault,
    output logic [31:0] commit_cause
);
    localparam logic [31:0] UART_TX_ADDR     = 32'h1000_0000;
    localparam logic [31:0] PERF_CYCLE_ADDR  = 32'h1000_0010;
    localparam logic [31:0] PERF_INST_ADDR   = 32'h1000_0014;
    localparam logic [31:0] PERF_STALL_ADDR  = 32'h1000_0018;
    localparam logic [31:0] PERF_BRANCH_ADDR = 32'h1000_001c;
    localparam logic [31:0] PERF_MISP_ADDR   = 32'h1000_0020;
    localparam logic [31:0] PERF_DIV_ADDR    = 32'h1000_0024;

    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [7:0]  dmem [0:DMEM_BYTES-1];

    logic [31:0] imem_addr, imem_rdata;
    logic        dmem_re, dmem_we;
    logic [1:0]  dmem_size;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        ram_access;
    logic [31:0] ram_word_addr;
    assign ram_word_addr = {dmem_addr[31:2], 2'b00};

    string hex_path;
    integer i;
    initial begin
        if (DMEM_BYTES < 4 || (DMEM_BYTES % 4) != 0 || IMEM_WORDS < 1)
            $fatal(1, "Memory parameters must describe positive whole words");
        for (i = 0; i < IMEM_WORDS; i = i + 1)
            imem[i] = 32'h00000013;
        for (i = 0; i < DMEM_BYTES; i = i + 1)
            dmem[i] = 8'h00;
        // A plusarg lets the regression reuse one compiled SoC for many tests.
        if ($value$plusargs("HEX=%s", hex_path))
            $readmemh(hex_path, imem);
        else if (IMEM_HEX != "")
            $readmemh(IMEM_HEX, imem);
    end

    always_comb begin
        if (imem_addr[31:2] < IMEM_WORDS)
            imem_rdata = imem[imem_addr[31:2]];
        else
            imem_rdata = 32'h00000013;
    end

    assign ram_access = (dmem_addr < DMEM_BYTES);

    always_comb begin
        dmem_rdata = 32'd0;

        if (ram_access && (ram_word_addr < DMEM_BYTES)) begin
            dmem_rdata = {
                dmem[ram_word_addr + 3],
                dmem[ram_word_addr + 2],
                dmem[ram_word_addr + 1],
                dmem[ram_word_addr + 0]
            };
        end else begin
            unique case (ram_word_addr)
                PERF_CYCLE_ADDR : dmem_rdata = cycle_count;
                PERF_INST_ADDR  : dmem_rdata = instret_count;
                PERF_STALL_ADDR : dmem_rdata = stall_count;
                PERF_BRANCH_ADDR: dmem_rdata = branch_count;
                PERF_MISP_ADDR  : dmem_rdata = mispredict_count;
                PERF_DIV_ADDR   : dmem_rdata = div_stall_count;
                default         : dmem_rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n && dmem_we) begin
            if (ram_access) begin
                unique case (dmem_size)
                    2'd0: begin
                        if (dmem_addr < DMEM_BYTES)
                            dmem[dmem_addr] <= dmem_wdata[7:0];
                    end
                    2'd1: begin
                        if (dmem_addr + 1 < DMEM_BYTES) begin
                            dmem[dmem_addr + 0] <= dmem_wdata[7:0];
                            dmem[dmem_addr + 1] <= dmem_wdata[15:8];
                        end
                    end
                    default: begin
                        if (dmem_addr + 3 < DMEM_BYTES) begin
                            dmem[dmem_addr + 0] <= dmem_wdata[7:0];
                            dmem[dmem_addr + 1] <= dmem_wdata[15:8];
                            dmem[dmem_addr + 2] <= dmem_wdata[23:16];
                            dmem[dmem_addr + 3] <= dmem_wdata[31:24];
                        end
                    end
                endcase
            end else if (dmem_addr == UART_TX_ADDR) begin
                $write("%c", dmem_wdata[7:0]);
            end
        end
    end

    rv32_core #(.ITERATIVE_DIV(ITERATIVE_DIV), .ENABLE_BP(ENABLE_BP), .BP_ENTRIES(BP_ENTRIES)) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_re(dmem_re), .dmem_we(dmem_we), .dmem_size(dmem_size),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .halted(halted),
        .cycle_count(cycle_count),
        .instret_count(instret_count),
        .stall_count(stall_count),
        .branch_count(branch_count),
        .mispredict_count(mispredict_count), .div_stall_count(div_stall_count),
        .faulted(faulted), .fault_cause(fault_cause), .fault_pc(fault_pc),
        .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_instr(commit_instr),
        .commit_rd(commit_rd), .commit_wdata(commit_wdata),
        .commit_mem_we(commit_mem_we), .commit_mem_addr(commit_mem_addr),
        .commit_mem_wdata(commit_mem_wdata), .commit_mem_size(commit_mem_size),
        .commit_stop(commit_stop), .commit_fault(commit_fault), .commit_cause(commit_cause)
    );
endmodule
