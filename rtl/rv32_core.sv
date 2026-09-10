module rv32_core (
    input  logic        clk,
    input  logic        rst_n,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    output logic        dmem_re,
    output logic        dmem_we,
    output logic [1:0]  dmem_size,      // 0=byte,1=half,2=word
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,

    output logic        halted,
    output logic [31:0] cycle_count,
    output logic [31:0] instret_count,
    output logic [31:0] stall_count,
    output logic [31:0] branch_count,
    output logic [31:0] mispredict_count
);

    // ----------------------------------------------------------------
    // ISA constants
    // ----------------------------------------------------------------
    localparam [6:0] OPC_LUI    = 7'b0110111;
    localparam [6:0] OPC_AUIPC  = 7'b0010111;
    localparam [6:0] OPC_JAL    = 7'b1101111;
    localparam [6:0] OPC_JALR   = 7'b1100111;
    localparam [6:0] OPC_BRANCH = 7'b1100011;
    localparam [6:0] OPC_LOAD   = 7'b0000011;
    localparam [6:0] OPC_STORE  = 7'b0100011;
    localparam [6:0] OPC_OPIMM  = 7'b0010011;
    localparam [6:0] OPC_OP     = 7'b0110011;
    localparam [6:0] OPC_SYSTEM = 7'b1110011;

    localparam [3:0] ALU_ADD  = 4'd0;
    localparam [3:0] ALU_SUB  = 4'd1;
    localparam [3:0] ALU_SLL  = 4'd2;
    localparam [3:0] ALU_SLT  = 4'd3;
    localparam [3:0] ALU_SLTU = 4'd4;
    localparam [3:0] ALU_XOR  = 4'd5;
    localparam [3:0] ALU_SRL  = 4'd6;
    localparam [3:0] ALU_SRA  = 4'd7;
    localparam [3:0] ALU_OR   = 4'd8;
    localparam [3:0] ALU_AND  = 4'd9;

    localparam [2:0] WB_ALU = 3'd0;
    localparam [2:0] WB_MEM = 3'd1;
    localparam [2:0] WB_PC4 = 3'd2;

    // ----------------------------------------------------------------
    // Program counter / IF stage
    // ----------------------------------------------------------------
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic        bp_predict_taken;
    logic [31:0] bp_predict_target;
    logic        bp_update_valid;
    logic        bp_update_taken;
    logic [31:0] bp_update_pc;
    logic [31:0] bp_update_target;

    assign imem_addr = pc;

    rv32_branch_predictor #(.ENTRIES(256)) u_bp (
        .clk(clk), .rst_n(rst_n),
        .fetch_pc(pc),
        .predict_taken(bp_predict_taken),
        .predict_target(bp_predict_target),
        .update_valid(bp_update_valid),
        .update_pc(bp_update_pc),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc               <= 32'd0;
            cycle_count      <= 32'd0;
            instret_count    <= 32'd0;
            stall_count      <= 32'd0;
            branch_count     <= 32'd0;
            mispredict_count <= 32'd0;
        end else if (!halted) begin
            pc          <= pc_next;
            cycle_count <= cycle_count + 32'd1;
            if (memwb_valid) instret_count <= instret_count + 32'd1;
            if (load_use_stall) stall_count <= stall_count + 32'd1;
            if (idex_valid && (idex_is_branch || idex_is_jal || idex_is_jalr))
                branch_count <= branch_count + 32'd1;
            if (ex_mispredict) mispredict_count <= mispredict_count + 32'd1;
        end
    end

    // ----------------------------------------------------------------
    // IF/ID pipeline register
    // ----------------------------------------------------------------
    logic        ifid_valid;
    logic [31:0] ifid_pc;
    logic [31:0] ifid_instr;
    logic        ifid_pred_taken;
    logic [31:0] ifid_pred_target;

    // ----------------------------------------------------------------
    // Decode
    // ----------------------------------------------------------------
    logic [6:0]  id_opcode;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [4:0]  id_rs1, id_rs2, id_rd;
    logic [31:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;
    logic [31:0] id_rdata1_raw, id_rdata2_raw;
    logic [31:0] id_rdata1, id_rdata2;

    assign id_opcode = ifid_instr[6:0];
    assign id_rd     = ifid_instr[11:7];
    assign id_funct3 = ifid_instr[14:12];
    assign id_rs1    = ifid_instr[19:15];
    assign id_rs2    = ifid_instr[24:20];
    assign id_funct7 = ifid_instr[31:25];

    rv32_imm_gen u_imm (
        .instr(ifid_instr),
        .imm_i(id_imm_i), .imm_s(id_imm_s), .imm_b(id_imm_b),
        .imm_u(id_imm_u), .imm_j(id_imm_j)
    );

    // ----------------------------------------------------------------
    // WB signals declared early for register file / WB->ID bypass
    // ----------------------------------------------------------------
    logic        memwb_valid;
    logic        memwb_regwrite;
    logic [4:0]  memwb_rd;
    logic [2:0]  memwb_wb_sel;
    logic [31:0] memwb_alu_result;
    logic [31:0] memwb_mem_data;
    logic [31:0] memwb_pc4;
    logic [31:0] wb_data;

    rv32_regfile u_rf (
        .clk(clk), .rst_n(rst_n),
        .we(memwb_valid && memwb_regwrite),
        .waddr(memwb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2),
        .rdata1(id_rdata1_raw), .rdata2(id_rdata2_raw)
    );

    always_comb begin
        unique case (memwb_wb_sel)
            WB_MEM: wb_data = memwb_mem_data;
            WB_PC4: wb_data = memwb_pc4;
            default: wb_data = memwb_alu_result;
        endcase
    end

    // Explicit WB->ID bypass avoids read/write same-cycle ambiguity.
    always_comb begin
        id_rdata1 = id_rdata1_raw;
        id_rdata2 = id_rdata2_raw;

        if (memwb_valid && memwb_regwrite && (memwb_rd != 0) && (memwb_rd == id_rs1))
            id_rdata1 = wb_data;
        if (memwb_valid && memwb_regwrite && (memwb_rd != 0) && (memwb_rd == id_rs2))
            id_rdata2 = wb_data;
    end

    // ----------------------------------------------------------------
    // Decode control
    // ----------------------------------------------------------------
    logic        id_regwrite, id_memread, id_memwrite;
    logic        id_use_imm, id_use_pc;
    logic        id_uses_rs1, id_uses_rs2;
    logic        id_is_branch, id_is_jal, id_is_jalr;
    logic        id_is_lui, id_is_auipc;
    logic        id_is_ecall;
    logic        id_is_muldiv;
    logic [2:0]  id_muldiv_op;
    logic [3:0]  id_alu_op;
    logic [2:0]  id_wb_sel;
    logic [31:0] id_imm;
    logic [1:0]  id_mem_size;
    logic        id_load_unsigned;

    always_comb begin
        id_regwrite      = 1'b0;
        id_memread       = 1'b0;
        id_memwrite      = 1'b0;
        id_use_imm       = 1'b0;
        id_use_pc        = 1'b0;
        id_uses_rs1      = 1'b0;
        id_uses_rs2      = 1'b0;
        id_is_branch     = 1'b0;
        id_is_jal        = 1'b0;
        id_is_jalr       = 1'b0;
        id_is_lui        = 1'b0;
        id_is_auipc      = 1'b0;
        id_is_ecall      = 1'b0;
        id_is_muldiv     = 1'b0;
        id_muldiv_op     = 3'b000;
        id_alu_op        = ALU_ADD;
        id_wb_sel        = WB_ALU;
        id_imm           = 32'd0;
        id_mem_size      = 2'd2;
        id_load_unsigned = 1'b0;

        unique case (id_opcode)
            OPC_OP: begin
                id_regwrite = 1'b1;
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                if (id_funct7 == 7'b0000001) begin
                    id_is_muldiv = 1'b1;
                    id_muldiv_op = id_funct3;
                end else begin
                    unique case (id_funct3)
                        3'b000: id_alu_op = id_funct7[5] ? ALU_SUB : ALU_ADD;
                        3'b001: id_alu_op = ALU_SLL;
                        3'b010: id_alu_op = ALU_SLT;
                        3'b011: id_alu_op = ALU_SLTU;
                        3'b100: id_alu_op = ALU_XOR;
                        3'b101: id_alu_op = id_funct7[5] ? ALU_SRA : ALU_SRL;
                        3'b110: id_alu_op = ALU_OR;
                        3'b111: id_alu_op = ALU_AND;
                        default: id_alu_op = ALU_ADD;
                    endcase
                end
            end

            OPC_OPIMM: begin
                id_regwrite = 1'b1;
                id_uses_rs1 = 1'b1;
                id_use_imm  = 1'b1;
                id_imm      = id_imm_i;
                unique case (id_funct3)
                    3'b000: id_alu_op = ALU_ADD;
                    3'b010: id_alu_op = ALU_SLT;
                    3'b011: id_alu_op = ALU_SLTU;
                    3'b100: id_alu_op = ALU_XOR;
                    3'b110: id_alu_op = ALU_OR;
                    3'b111: id_alu_op = ALU_AND;
                    3'b001: id_alu_op = ALU_SLL;
                    3'b101: id_alu_op = ifid_instr[30] ? ALU_SRA : ALU_SRL;
                    default: id_alu_op = ALU_ADD;
                endcase
            end

            OPC_LOAD: begin
                id_regwrite = 1'b1;
                id_memread  = 1'b1;
                id_uses_rs1 = 1'b1;
                id_use_imm  = 1'b1;
                id_imm      = id_imm_i;
                id_alu_op   = ALU_ADD;
                id_wb_sel   = WB_MEM;
                unique case (id_funct3)
                    3'b000: begin id_mem_size=2'd0; id_load_unsigned=1'b0; end // LB
                    3'b001: begin id_mem_size=2'd1; id_load_unsigned=1'b0; end // LH
                    3'b010: begin id_mem_size=2'd2; id_load_unsigned=1'b0; end // LW
                    3'b100: begin id_mem_size=2'd0; id_load_unsigned=1'b1; end // LBU
                    3'b101: begin id_mem_size=2'd1; id_load_unsigned=1'b1; end // LHU
                    default: begin id_mem_size=2'd2; id_load_unsigned=1'b0; end
                endcase
            end

            OPC_STORE: begin
                id_memwrite = 1'b1;
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                id_use_imm  = 1'b1;
                id_imm      = id_imm_s;
                id_alu_op   = ALU_ADD;
                unique case (id_funct3)
                    3'b000: id_mem_size = 2'd0; // SB
                    3'b001: id_mem_size = 2'd1; // SH
                    default: id_mem_size = 2'd2; // SW
                endcase
            end

            OPC_BRANCH: begin
                id_is_branch = 1'b1;
                id_uses_rs1  = 1'b1;
                id_uses_rs2  = 1'b1;
                id_imm       = id_imm_b;
            end

            OPC_JAL: begin
                id_regwrite = 1'b1;
                id_is_jal   = 1'b1;
                id_imm      = id_imm_j;
                id_wb_sel   = WB_PC4;
            end

            OPC_JALR: begin
                id_regwrite = 1'b1;
                id_is_jalr  = 1'b1;
                id_uses_rs1 = 1'b1;
                id_imm      = id_imm_i;
                id_wb_sel   = WB_PC4;
            end

            OPC_LUI: begin
                id_regwrite = 1'b1;
                id_is_lui   = 1'b1;
                id_imm      = id_imm_u;
            end

            OPC_AUIPC: begin
                id_regwrite = 1'b1;
                id_is_auipc = 1'b1;
                id_use_pc   = 1'b1;
                id_use_imm  = 1'b1;
                id_imm      = id_imm_u;
                id_alu_op   = ALU_ADD;
            end

            OPC_SYSTEM: begin
                if (ifid_instr == 32'h00000073)
                    id_is_ecall = 1'b1; // simulation stop convention
            end

            default: begin end
        endcase
    end

    // ----------------------------------------------------------------
    // ID/EX pipeline
    // ----------------------------------------------------------------
    logic        idex_valid;
    logic [31:0] idex_pc, idex_pc4;
    logic [31:0] idex_rs1_val, idex_rs2_val, idex_imm;
    logic [4:0]  idex_rs1, idex_rs2, idex_rd;
    logic [2:0]  idex_funct3;
    logic [3:0]  idex_alu_op;
    logic [2:0]  idex_wb_sel;
    logic [1:0]  idex_mem_size;
    logic        idex_load_unsigned;
    logic        idex_regwrite, idex_memread, idex_memwrite;
    logic        idex_use_imm, idex_use_pc;
    logic        idex_is_branch, idex_is_jal, idex_is_jalr;
    logic        idex_is_lui, idex_is_ecall;
    logic        idex_is_muldiv;
    logic [2:0]  idex_muldiv_op;
    logic        idex_pred_taken;
    logic [31:0] idex_pred_target;

    // Load-use hazard detector.
    logic load_use_stall;
    always_comb begin
        load_use_stall = 1'b0;
        if (idex_valid && idex_memread && (idex_rd != 0) && ifid_valid) begin
            if ((id_uses_rs1 && (idex_rd == id_rs1)) ||
                (id_uses_rs2 && (idex_rd == id_rs2)))
                load_use_stall = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // EX stage forwarding
    // ----------------------------------------------------------------
    logic        exmem_valid;
    logic        exmem_regwrite, exmem_memread, exmem_memwrite;
    logic [4:0]  exmem_rd;
    logic [2:0]  exmem_wb_sel;
    logic [1:0]  exmem_mem_size;
    logic        exmem_load_unsigned;
    logic [31:0] exmem_alu_result, exmem_store_data, exmem_pc4;

    logic [31:0] ex_rs1_fwd, ex_rs2_fwd;
    logic [31:0] exmem_forward_value;

    // Cannot forward load data from EX/MEM before memory has produced it.
    assign exmem_forward_value = (exmem_wb_sel == WB_PC4) ? exmem_pc4 : exmem_alu_result;

    always_comb begin
        ex_rs1_fwd = idex_rs1_val;
        ex_rs2_fwd = idex_rs2_val;

        if (exmem_valid && exmem_regwrite && !exmem_memread &&
            (exmem_rd != 0) && (exmem_rd == idex_rs1))
            ex_rs1_fwd = exmem_forward_value;
        else if (memwb_valid && memwb_regwrite &&
                 (memwb_rd != 0) && (memwb_rd == idex_rs1))
            ex_rs1_fwd = wb_data;

        if (exmem_valid && exmem_regwrite && !exmem_memread &&
            (exmem_rd != 0) && (exmem_rd == idex_rs2))
            ex_rs2_fwd = exmem_forward_value;
        else if (memwb_valid && memwb_regwrite &&
                 (memwb_rd != 0) && (memwb_rd == idex_rs2))
            ex_rs2_fwd = wb_data;
    end

    logic [31:0] ex_alu_a, ex_alu_b, ex_alu_y;
    logic [31:0] ex_muldiv_y;
    logic [31:0] ex_exec_y;
    always_comb begin
        ex_alu_a = idex_use_pc ? idex_pc : ex_rs1_fwd;
        ex_alu_b = idex_use_imm ? idex_imm : ex_rs2_fwd;

        if (idex_is_lui) begin
            ex_alu_a = 32'd0;
            ex_alu_b = idex_imm;
        end
    end

    rv32_alu u_alu(.a(ex_alu_a), .b(ex_alu_b), .op(idex_alu_op), .y(ex_alu_y));
    rv32_muldiv_unit u_muldiv(
        .a(ex_rs1_fwd), .b(ex_rs2_fwd), .op(idex_muldiv_op), .y(ex_muldiv_y)
    );
    assign ex_exec_y = idex_is_muldiv ? ex_muldiv_y : ex_alu_y;

    // Branch / jump resolution in EX + dynamic prediction recovery.
    logic        ex_branch_taken;
    logic        ex_actual_taken;
    logic [31:0] ex_actual_target;
    logic        ex_mispredict;
    logic [31:0] ex_recovery_pc;

    always_comb begin
        ex_branch_taken = 1'b0;
        if (idex_is_branch) begin
            unique case (idex_funct3)
                3'b000: ex_branch_taken = (ex_rs1_fwd == ex_rs2_fwd);                  // BEQ
                3'b001: ex_branch_taken = (ex_rs1_fwd != ex_rs2_fwd);                  // BNE
                3'b100: ex_branch_taken = ($signed(ex_rs1_fwd) < $signed(ex_rs2_fwd)); // BLT
                3'b101: ex_branch_taken = ($signed(ex_rs1_fwd) >= $signed(ex_rs2_fwd));// BGE
                3'b110: ex_branch_taken = (ex_rs1_fwd < ex_rs2_fwd);                   // BLTU
                3'b111: ex_branch_taken = (ex_rs1_fwd >= ex_rs2_fwd);                  // BGEU
                default: ex_branch_taken = 1'b0;
            endcase
        end

        ex_actual_taken = idex_is_jal || idex_is_jalr ||
                          (idex_is_branch && ex_branch_taken);

        if (idex_is_jalr)
            ex_actual_target = (ex_rs1_fwd + idex_imm) & 32'hffff_fffe;
        else
            ex_actual_target = idex_pc + idex_imm;

        ex_mispredict = idex_valid && (idex_is_branch || idex_is_jal || idex_is_jalr) &&
                        ((idex_pred_taken != ex_actual_taken) ||
                         (ex_actual_taken && idex_pred_taken &&
                          (idex_pred_target != ex_actual_target)));

        ex_recovery_pc = ex_actual_taken ? ex_actual_target : idex_pc4;
    end

    assign bp_update_valid  = idex_valid && (idex_is_branch || idex_is_jal || idex_is_jalr);
    assign bp_update_pc     = idex_pc;
    assign bp_update_taken  = ex_actual_taken;
    assign bp_update_target = ex_actual_target;

    // Next-PC priority: misprediction recovery > load-use stall > prediction.
    always_comb begin
        if (ex_mispredict)
            pc_next = ex_recovery_pc;
        else if (load_use_stall)
            pc_next = pc;
        else if (bp_predict_taken)
            pc_next = bp_predict_target;
        else
            pc_next = pc + 32'd4;
    end

    // ----------------------------------------------------------------
    // Pipeline register updates
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'd0;
            ifid_instr <= 32'h00000013; // NOP
            ifid_pred_taken <= 1'b0;
            ifid_pred_target <= 32'd0;
        end else if (!halted) begin
            if (ex_mispredict) begin
                ifid_valid <= 1'b0;
                ifid_instr <= 32'h00000013;
                ifid_pred_taken <= 1'b0;
                ifid_pred_target <= 32'd0;
            end else if (!load_use_stall) begin
                ifid_valid       <= 1'b1;
                ifid_pc          <= pc;
                ifid_instr       <= imem_rdata;
                ifid_pred_taken  <= bp_predict_taken;
                ifid_pred_target <= bp_predict_target;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_valid         <= 1'b0;
            idex_pc            <= 0;
            idex_pc4           <= 0;
            idex_rs1_val       <= 0;
            idex_rs2_val       <= 0;
            idex_imm           <= 0;
            idex_rs1           <= 0;
            idex_rs2           <= 0;
            idex_rd            <= 0;
            idex_funct3        <= 0;
            idex_alu_op        <= ALU_ADD;
            idex_wb_sel        <= WB_ALU;
            idex_mem_size      <= 2'd2;
            idex_load_unsigned <= 0;
            idex_regwrite      <= 0;
            idex_memread       <= 0;
            idex_memwrite      <= 0;
            idex_use_imm       <= 0;
            idex_use_pc        <= 0;
            idex_is_branch     <= 0;
            idex_is_jal        <= 0;
            idex_is_jalr       <= 0;
            idex_is_lui        <= 0;
            idex_is_ecall      <= 0;
            idex_is_muldiv     <= 0;
            idex_muldiv_op     <= 0;
            idex_pred_taken    <= 0;
            idex_pred_target   <= 0;
        end else if (!halted) begin
            if (ex_mispredict || load_use_stall) begin
                idex_valid <= 1'b0; // flush or bubble
            end else begin
                idex_valid         <= ifid_valid;
                idex_pc            <= ifid_pc;
                idex_pc4           <= ifid_pc + 32'd4;
                idex_rs1_val       <= id_rdata1;
                idex_rs2_val       <= id_rdata2;
                idex_imm           <= id_imm;
                idex_rs1           <= id_rs1;
                idex_rs2           <= id_rs2;
                idex_rd            <= id_rd;
                idex_funct3        <= id_funct3;
                idex_alu_op        <= id_alu_op;
                idex_wb_sel        <= id_wb_sel;
                idex_mem_size      <= id_mem_size;
                idex_load_unsigned <= id_load_unsigned;
                idex_regwrite      <= id_regwrite;
                idex_memread       <= id_memread;
                idex_memwrite      <= id_memwrite;
                idex_use_imm       <= id_use_imm;
                idex_use_pc        <= id_use_pc;
                idex_is_branch     <= id_is_branch;
                idex_is_jal        <= id_is_jal;
                idex_is_jalr       <= id_is_jalr;
                idex_is_lui        <= id_is_lui;
                idex_is_ecall      <= id_is_ecall;
                idex_is_muldiv     <= id_is_muldiv;
                idex_muldiv_op     <= id_muldiv_op;
                idex_pred_taken    <= ifid_pred_taken;
                idex_pred_target   <= ifid_pred_target;
            end
        end
    end

    // Halt when ECALL reaches EX. This is a simulation convention, not a trap unit.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            halted <= 1'b0;
        else if (idex_valid && idex_is_ecall)
            halted <= 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_valid         <= 0;
            exmem_regwrite      <= 0;
            exmem_memread       <= 0;
            exmem_memwrite      <= 0;
            exmem_rd            <= 0;
            exmem_wb_sel        <= WB_ALU;
            exmem_mem_size      <= 2'd2;
            exmem_load_unsigned <= 0;
            exmem_alu_result    <= 0;
            exmem_store_data    <= 0;
            exmem_pc4           <= 0;
        end else if (!halted) begin
            exmem_valid         <= idex_valid;
            exmem_regwrite      <= idex_regwrite;
            exmem_memread       <= idex_memread;
            exmem_memwrite      <= idex_memwrite;
            exmem_rd            <= idex_rd;
            exmem_wb_sel        <= idex_wb_sel;
            exmem_mem_size      <= idex_mem_size;
            exmem_load_unsigned <= idex_load_unsigned;
            exmem_alu_result    <= ex_exec_y;
            exmem_store_data    <= ex_rs2_fwd;
            exmem_pc4           <= idex_pc4;
        end
    end

    // ----------------------------------------------------------------
    // MEM stage
    // ----------------------------------------------------------------
    assign dmem_re    = exmem_valid && exmem_memread;
    assign dmem_we    = exmem_valid && exmem_memwrite;
    assign dmem_size  = exmem_mem_size;
    assign dmem_addr  = exmem_alu_result;
    assign dmem_wdata = exmem_store_data;

    logic [31:0] load_data_ext;
    logic [7:0]  load_byte;
    logic [15:0] load_half;

    always_comb begin
        unique case (exmem_alu_result[1:0])
            2'd0: load_byte = dmem_rdata[7:0];
            2'd1: load_byte = dmem_rdata[15:8];
            2'd2: load_byte = dmem_rdata[23:16];
            default: load_byte = dmem_rdata[31:24];
        endcase

        load_half = exmem_alu_result[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

        unique case (exmem_mem_size)
            2'd0: load_data_ext = exmem_load_unsigned ?
                                  {24'd0, load_byte} :
                                  {{24{load_byte[7]}}, load_byte};
            2'd1: load_data_ext = exmem_load_unsigned ?
                                  {16'd0, load_half} :
                                  {{16{load_half[15]}}, load_half};
            default: load_data_ext = dmem_rdata;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_valid      <= 0;
            memwb_regwrite   <= 0;
            memwb_rd         <= 0;
            memwb_wb_sel     <= WB_ALU;
            memwb_alu_result <= 0;
            memwb_mem_data   <= 0;
            memwb_pc4        <= 0;
        end else if (!halted) begin
            memwb_valid      <= exmem_valid;
            memwb_regwrite   <= exmem_regwrite;
            memwb_rd         <= exmem_rd;
            memwb_wb_sel     <= exmem_wb_sel;
            memwb_alu_result <= exmem_alu_result;
            memwb_mem_data   <= load_data_ext;
            memwb_pc4        <= exmem_pc4;
        end
    end

endmodule
