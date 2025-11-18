`timescale 1ns / 1ps
import types_pkg::*;

module res_station(
    input clk,
    input reset,
    
    // from rename
    input rename_data r_data,
    input logic [1:0] fu_in,
    input logic [6:0] Opcode,
    
    // from fu
    input logic mispredict,
    input logic [4:0] mispredict_tag,
    input logic [6:0] ps_in,
    input logic ps_ready,
    input logic fu_ready,
    
    // from ROB
    input logic [4:0] rob_index_in,
    
    // from Dispatch
    input logic di_en,
    input logic preg_rtable[0:127],
        
    // Output
    output logic fu_dispatched,
    output logic full,
    output rs_data data_out
);
    rs_data rs_table [0:7];
    
    logic [3:0] in_idx;
    logic [3:0] out_idx;
    assign data_out = rs_table[out_idx];
    logic in_valid;
    logic out_ready;
    
    assign full = ~in_valid;
    always_comb begin
        in_valid = 1'b0;
        out_ready = 1'b0;
        for (int i = 0; i <= 7; i++) begin
            if (!in_valid && !rs_table[i].valid) begin
                in_idx = i;
                in_valid = 1'b1;
            end
            if (!out_ready && rs_table[i].ready && rs_table[i].valid) begin
                out_idx = i;
                out_ready = 1'b1;
            end
            if (in_valid && out_ready) begin
                break;
            end
        end
    end
        
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (logic [2:0] i = 0; i <= 7; i++) begin
                rs_table[i] <= '0;
            end
            in_idx <= '0;
            out_idx <= '0; 
        end else begin
            fu_dispatched <= 1'b0;
//            if (mispredict) begin
//                automatic logic [4:0] re_ptr = (mispredict_tag==15)?0:mispredict_tag+1;
//                for (logic [4:0] i=re_ptr; i!=rob_index_in; i=(i==15)?0:i+1) begin
//                    rs_table[i] <= '0;
//                end
//            end
            if (ps_ready) begin
                for (logic [3:0] i = 0; i < 8; i++) begin
                    if (rs_table[i].valid) begin
                        if (!rs_table[i].ps1_ready && rs_table[i].ps1 == ps_in) begin
                            rs_table[i].ps1_ready <= 1'b1;
                        end 
                        if (!rs_table[i].ps2_ready && rs_table[i].ps2 == ps_in) begin
                            rs_table[i].ps2_ready <= 1'b1;
                        end
                    end
                end
            end
            for (logic [3:0] i = 0; i < 8; i++) begin
                if (rs_table[i].valid) begin
                    if (rs_table[i].ps1_ready && rs_table[i].ps2_ready && fu_ready) begin
                        rs_table[i].ready <= 1'b1;
                    end
                end
            end
            if (out_ready) begin
                rs_table[out_idx] <= '0;
                fu_dispatched <= 1'b1;
            end
            // Dispatch to RS
            if (in_valid && di_en) begin
                rs_table[in_idx].fu <= fu_in;
                rs_table[in_idx].valid <= 1'b1;
                rs_table[in_idx].Opcode <= Opcode;
                rs_table[in_idx].pd <= r_data.pd_new;
                rs_table[in_idx].ps1 <= r_data.ps1;
                rs_table[in_idx].ps2 <= r_data.ps2;
                rs_table[in_idx].imm <= r_data.imm;
                rs_table[in_idx].rob_index <= rob_index_in;
                rs_table[in_idx].ps1_ready <= 1'b0;
                rs_table[in_idx].ps2_ready <= 1'b0;
                if (preg_rtable[r_data.ps1] && preg_rtable[r_data.ps2] && fu_ready) begin
                    rs_table[in_idx].ready <= 1'b1;
                    rs_table[in_idx].ps1_ready <= 1'b1;
                    rs_table[in_idx].ps2_ready <= 1'b1;
                end else begin
                    if (preg_rtable[r_data.ps1]) begin
                        rs_table[in_idx].ps1_ready <= 1'b1;
                    end
                    if (preg_rtable[r_data.ps2]) begin
                        rs_table[in_idx].ps2_ready <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
