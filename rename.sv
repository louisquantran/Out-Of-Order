`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/09/2025 07:52:52 PM
// Design Name: 
// Module Name: rename
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

import types_pkg::*;

module rename(
    input logic clk,
    input logic reset,

    // Data from skid buffer
    // Upstream
    input logic valid_in,  
    input decode_data data_in,
    output logic ready_in,
    
    // Mispredict signal from ROB
    input logic mispredict,
    
    // Downstream
    output rename_data data_out,
    output logic valid_out,
    input logic ready_out
);
    logic read_en;
    logic write_en;
    logic [7:0] preg;
    logic full;
    logic update_en; 
    
    logic [4:0] map [0:31];
    
    assign ready_in = ready_out;
    assign valid_out = valid_in;
    
    always_comb begin
        data_out.imm = data_in.imm;
        data_out.pd_old = map[data_in.rd];
        data_out.pd_new = '0;
        data_out.ps1 = '0;
        data_out.ps2 = '0;
        if (preg == 8'b0) begin
            ready_in = 1'b0;
        end else begin
            ready_in = 1'b1;
            if (data_in.Opcode != 7'b0100011) begin
                update_en = 1'b1;
                write_en = 1'b1;
                data_out.ps1 = map[data_in.rs1];
                data_out.ps2 = map[data_in.rs2];
                data_out.pd_new = preg;
            end else begin
                update_en = 1'b0;
                write_en = 1'b0;
                data_out.ps1 = map[data_in.rs1];
                data_out.ps2 = map[data_in.rs2];
            end
        end
    end
    
    map_table u_map_table(
        .clk(clk),
        .reset(reset), 
        .update_en(update_en),
        .rd(data_in.rd),
        .pd_new(preg),
        .map(map)
    );
    free_list u_free_list(
        .clk(clk),
        .reset(reset),
        .write_en(write_en),    
        .read_en(read_en),
        .head(preg)
    );
endmodule
