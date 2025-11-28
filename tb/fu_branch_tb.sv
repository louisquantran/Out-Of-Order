`timescale 1ns / 1ps

// Ensure types_pkg is compiled before this file
import types_pkg::*;

module tb_fu_branch;

    // Signal Declarations
    logic clk;
    logic reset;

    // Inputs from RS
    rs_data data_in;
    logic issued;

    // Inputs from PRF
    logic [31:0] ps1_data;
    logic [31:0] ps2_data;

    // Outputs
    b_data data_out;

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // DUT Instantiation
    fu_branch dut (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .issued(issued),
        .ps1_data(ps1_data),
        .ps2_data(ps2_data),
        .data_out(data_out)
    );

    // Test Procedure
    initial begin
        // Initialize Inputs
        issued = 0;
        data_in = '0;
        ps1_data = 0;
        ps2_data = 0;
        
        // 1. Reset Test
        $display("--- Starting Reset Test ---");
        reset = 1;
        @(posedge clk);
        #1; // Post-hold
        reset = 0;
        
        assert(data_out.fu_b_ready == 1'b1) else $error("Reset failed: fu_b_ready should be 1");
        assert(data_out.fu_b_done == 1'b0)  else $error("Reset failed: fu_b_done should be 0");
        $display("Reset Test Passed");
        
        // 2. JALR Test (Opcode 7'b1100111, func3 000)
        $display("\n--- Starting JALR Test ---");
        
        // Setup JALR: Target = rs1 + imm
        // PC = 1000, RS1 = 500, Imm = 20 -> Target should be 520
        // Return Address (data) should be PC + 4 = 1004
        
        @(negedge clk);
        issued = 1;
        data_in.Opcode = 7'b1100111;
        data_in.func3  = 3'b000;
        data_in.pc     = 32'd1000;
        data_in.imm    = 32'd20;
        data_in.pd     = 7'd5;     // Dest physical reg
        ps1_data       = 32'd500;  // Base address
        ps2_data       = 32'd0;    // Unused for JALR

        @(posedge clk);
        #1; // Check after clock edge
        
        // Verify output
        if (data_out.fu_b_done && 
            data_out.jalr_bne_signal && 
            data_out.pc == 32'd520 && 
            data_out.data == 32'd1004 &&
            data_out.p_b == 7'd5) begin
            $display("JALR Test Passed: Target=520, RetAddr=1004");
        end else begin
            $error("JALR Test Failed! Got: PC=%d, Data=%d, Done=%b", 
                   data_out.pc, data_out.data, data_out.fu_b_done);
        end

        // Deassert issue
        @(negedge clk);
        issued = 0;
        @(posedge clk);

        // 3. BNE Test - Mispredict (Taken)
        $display("\n--- Starting BNE (Mispredict/Taken) Test ---");
        // Logic assumes Not Taken. If taken (rs1 != rs2), it is a mispredict.
        // Opcode 7'b1100011, func3 001
        
        @(negedge clk);
        issued = 1;
        data_in.Opcode    = 7'b1100011;
        data_in.func3     = 3'b001;
        data_in.pc        = 32'd2000;
        data_in.imm       = 32'd100;
        data_in.rob_index = 5'd12; // Tag 12
        
        ps1_data = 32'd10;
        ps2_data = 32'd20; // 10 != 20, so Branch IS Taken
        
        @(posedge clk);
        #1; 

        // Expected: Mispredict = 1, PC = 2100, Tag = 12
        if (data_out.mispredict == 1'b1 && 
            data_out.mispredict_tag == 5'd12 && 
            data_out.pc == 32'd2100) begin
            $display("BNE (Taken) Test Passed: Correctly flagged mispredict to PC 2100");
        end else begin
            $error("BNE (Taken) Test Failed! Mispredict=%b, PC=%d", data_out.mispredict, data_out.pc);
        end

        // 4. BNE Test - Correct Predict (Not Taken)
        $display("\n--- Starting BNE (Correct/Not Taken) Test ---");
        
        @(negedge clk);
        issued = 1;
        // Keep opcode BNE
        // Make inputs Equal so branch is NOT taken
        ps1_data = 32'd50;
        ps2_data = 32'd50; 
        
        @(posedge clk);
        #1;

        // Expected: Mispredict = 0, PC = 0 (or don't care, logic sets to 0)
        if (data_out.mispredict == 1'b0 && data_out.fu_b_done == 1'b1) begin
             $display("BNE (Not Taken) Test Passed: No mispredict flagged.");
        end else begin
             $error("BNE (Not Taken) Test Failed! Mispredict should be 0. Got %b", data_out.mispredict);
        end

        // End Simulation
        @(negedge clk);
        issued = 0;
        #20;
        $display("\n--- All Tests Complete ---");
        $finish;
    end

endmodule