`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/17/2025 09:38:18 PM
// Design Name: 
// Module Name: dispatch
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module dispatch(
    input logic clk,
    input logic reset,
    // Upstream
    input logic valid_in,
    input rename_data data_in,
    output logic ready_in,
    
    // Data from ROB
    input logic rob_full,
    input logic [4:0] rob_index_in,
    
    // Data from FU
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [6:0] ps_in_alu,
    input logic [6:0] ps_in_b,
    input logic [6:0] ps_in_mem,
    input logic ps_alu_ready,
    input logic ps_b_ready,
    input logic ps_mem_ready,
    input logic fu_alu_ready,
    input logic fu_b_ready,
    input logic fu_mem_ready,
    
    // Output data from 3 RS
    output rs_data rs_alu,
    output rs_data rs_b,
    output rs_data rs_mem,
    
    output logic alu_dispatched,
    output logic b_dispatched,
    output logic mem_dispatched
);
    logic rs_alu_full = '0;
    logic rs_b_full = '0;
    logic rs_mem_full = '0;
    logic di_en_alu = '0;
    logic di_en_b = '0;
    logic di_en_mem = '0;
    
    rename_data data_q;
    assign data_q = data_in;
        
    always_comb begin
        ready_in = !rob_full && (!rs_alu_full 
                    || !rs_b_full || !rs_mem_full);
        if (ready_in && valid_in) begin
            unique case (data_q.fu) 
                2'b01: begin
                    di_en_alu = 1'b1;
                    $display ("Set di_en_alu to 1 : %d", di_en_alu); 
                    $display("data_in.pd_new : %d", data_q.pd_new);
                end
                2'b10: di_en_b = 1'b1;
                2'b11: di_en_mem = 1'b1;
                default: begin
                    di_en_alu = 1'b0;
                    di_en_b = 1'b0;
                    di_en_mem = 1'b0;  
                end
            endcase
        end else begin
            di_en_alu = 1'b0;
            di_en_b = 1'b0;
            di_en_mem = 1'b0;
        end
    end
    
    logic preg_rtable[0:127];
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (logic [6:0] i = 0; i < 128; i++) begin
                preg_rtable[i] <= 1'b1;
            end
        end else begin
            // set that preg to 0
            if (di_en_alu) begin
                preg_rtable[data_q.pd_new] <= 1'b0;
            end
            if (di_en_mem) begin
                preg_rtable[data_q.pd_new] <= 1'b0; 
            end
            if (ps_alu_ready) begin
                preg_rtable[ps_in_alu] <= 1'b1;
            end 
            if (ps_b_ready) begin
                preg_rtable[ps_in_b] <= 1'b1;
            end 
            if (ps_mem_ready) begin
                preg_rtable[ps_in_mem] <= 1'b1;
            end
        end
    end
    
    res_station res_alu (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_alu
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .ps_in(ps_in_alu),
        .ps_ready(ps_alu_ready),
        .fu_ready(fu_alu_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_alu),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_dispatched(alu_dispatched),
        .full(rs_alu_full),
        .data_out(rs_alu)
    );
    
    res_station res_b (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_alu
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .ps_in(ps_in_b),
        .ps_ready(ps_b_ready),
        .fu_ready(fu_b_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_b),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_dispatched(b_dispatched),
        .full(rs_b_full),
        .data_out(rs_b)
    );
    
    res_station res_mem (
        .clk(clk),
        .reset(reset),
        
        // From rename
        .r_data(data_q),
        
        // From fu_alu
        .mispredict(mispredict),
        .mispredict_tag(mispredict_tag),
        .ps_in(ps_in_mem),
        .ps_ready(ps_mem_ready),
        .fu_ready(fu_mem_ready),
        
        // from ROB
        .rob_index_in(rob_index_in),
        
        // From dispatch
        .di_en(di_en_mem),
        .preg_rtable(preg_rtable),
        
        // Output data
        .fu_dispatched(mem_dispatched),
        .full(rs_mem_full),
        .data_out(rs_mem)
    );
    
endmodule
