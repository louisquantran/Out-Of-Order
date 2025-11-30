`timescale 1ns/1ps
import types_pkg::*;

module ooo_top_tb;

  // ---------------- Clock / Reset / DUT ----------------
  logic clk   = 0;
  logic reset = 1;
  logic exec_ready;

  localparam int CLK_PERIOD = 10;  // 100 MHz

  // Clock
  always #(CLK_PERIOD/2) clk = ~clk;

  // DUT
  ooo_top dut (
    .clk        (clk),
    .reset      (reset),
    .exec_ready (exec_ready)
  );

  // Simple helper
  task automatic run_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  // ---------------- Control (reset + run) ----------------
  initial begin
    $display("=== Starting ooo_top integration test ===");

    exec_ready = 1'b1;   // always ready for now

    // Apply reset for a few cycles
    reset = 1'b1;
    run_cycles(5);

    reset = 1'b0;
    $display("[%0t] Deassert reset", $time);
    $display("[%0t] Warm-up: letting instructions flow", $time);

    // Let the program run for a while
    run_cycles(200);

    $display("[%0t] Ending ooo_top integration test", $time);
    $finish;
  end

  // ---------------- Handy wires into DUT internals ----------------

  // Fetch fire (already computed inside ooo_top)
  wire fetch_fire_tb = dut.fetch_fire;

  // Simple branch "taken" indicator (for PC checker):
  // branch FU signals that a JALR/BNE-style redirect is happening
  wire branch_taken_tb = dut.b_out.fu_b_done && dut.b_out.jalr_bne_signal;

  // ---------------- PC Checker (fixed off-by-one) ----------------
  logic [31:0] prev_pc;
  logic        prev_branch_taken;
  logic [31:0] prev_branch_pc;
  logic        prev_fetch_fire;

  always_ff @(posedge clk) begin
    if (reset) begin
      prev_pc           <= 32'h0000_0000;
      prev_branch_taken <= 1'b0;
      prev_branch_pc    <= 32'h0000_0000;
      prev_fetch_fire   <= 1'b0;
    end else begin
      // We check the PC *one cycle after* the fetch that consumed an instruction.
      if (prev_fetch_fire) begin
        if (prev_branch_taken) begin
          // Expect PC to equal last branch target
          if (dut.pc_reg !== prev_branch_pc) begin
            $error("[%0t] PC mismatch on branch: got 0x%08h, expected 0x%08h",
                   $time, dut.pc_reg, prev_branch_pc);
          end else begin
            $display("[%0t] PC OK (branch) : pc_reg=0x%08h",
                     $time, dut.pc_reg);
          end
        end else begin
          // Expect sequential PC+4
          if (dut.pc_reg !== (prev_pc + 32'd4)) begin
            $error("[%0t] PC mismatch on sequential step: prev=0x%08h, got=0x%08h",
                   $time, prev_pc, dut.pc_reg);
          end else begin
            $display("[%0t] PC OK (seq)    : 0x%08h -> 0x%08h",
                     $time, prev_pc, dut.pc_reg);
          end
        end
      end

      // Update history for *next* cycle
      prev_pc           <= dut.pc_reg;
      prev_branch_taken <= branch_taken_tb;
      prev_branch_pc    <= dut.b_out.pc;
      prev_fetch_fire   <= fetch_fire_tb;
    end
  end

  // ---------------- Debug printing / pipeline tracing ----------------

  // FETCH
  always_ff @(posedge clk) begin
    if (!reset && fetch_fire_tb) begin
      fetch_data f = dut.fetch_out;
      $display("[%0t] FETCH : pc=0x%08h instr=0x%08h pc_4=0x%08h",
               $time, f.pc, f.instr, f.pc_4);
    end
  end

  // DECODE → RENAME (decode output)
  always_ff @(posedge clk) begin
    if (!reset && dut.v_decode) begin
      decode_data d = dut.decode_out;
      $display("[%0t] DEC→REN : pc=0x%08h rs1=%0d rs2=%0d rd=%0d opcode=0x%02h fu=%0d imm=0x%08h",
               $time, d.pc, d.rs1, d.rs2, d.rd, d.Opcode, d.fu, d.imm);
    end
  end

  // RENAME output
  always_ff @(posedge clk) begin
    if (!reset && dut.r_to_bf_di) begin
      rename_data r = dut.rename_out;
      $display("[%0t] RENAMEOUT : pc=0x%08h fu=%0d pd_new=%0d pd_old=%0d ps1=%0d ps2=%0d opcode=0x%02h imm=0x%08h rob_tag=%0d",
               $time, r.pc, r.fu, r.pd_new, r.pd_old, r.ps1, r.ps2,
               r.Opcode, r.imm[31:0], r.rob_tag);
    end
  end

  // RENAME → DISPATCH (post-rename skid out)
  always_ff @(posedge clk) begin
    if (!reset && dut.v_sb_to_di && dut.r_di_to_sb) begin
      rename_data r = dut.sb_to_di_out;
      $display("[%0t] REN→DIS : pc=0x%08h fu=%0d pd_new=%0d ps1=%0d ps2=%0d rob_tag=%0d",
               $time, r.pc, r.fu, r.pd_new, r.ps1, r.ps2, r.rob_tag);
    end
  end

  // ROB enqueue
  always_ff @(posedge clk) begin
    if (!reset && dut.rob_write_en) begin
      rename_data r = dut.sb_to_di_out;
      $display("[%0t] ROB ENQ : rob_idx=%0d pc=0x%08h pd_new=%0d pd_old=%0d",
               $time, dut.rob_index, r.pc, r.pd_new, r.pd_old);
    end
  end

  // ISSUE from RS: ALU / MEM / BR
  always_ff @(posedge clk) begin
    if (!reset && dut.alu_issued) begin
      rs_data ra = dut.rs_alu;
      $display("[%0t] ISSUE ALU : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, ra.rob_index, ra.pd, ra.ps1, ra.ps2);
    end

    if (!reset && dut.mem_issued) begin
      rs_data rm = dut.rs_mem;
      $display("[%0t] ISSUE MEM : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, rm.rob_index, rm.pd, rm.ps1, rm.ps2);
    end

    if (!reset && dut.b_issued) begin
      rs_data rb = dut.rs_b;
      $display("[%0t] ISSUE BR  : rob=%0d pd=%0d ps1=%0d ps2=%0d",
               $time, rb.rob_index, rb.pd, rb.ps1, rb.ps2);
    end
  end

  // FU completes: ALU / MEM / BR
  always_ff @(posedge clk) begin
    if (!reset && dut.alu_out.fu_alu_done) begin
      $display("[%0t] FU ALU DONE : rob=%0d pd=%0d data=0x%08h",
               $time, dut.alu_out.rob_fu_alu, dut.alu_out.p_alu, dut.alu_out.data);
    end

    if (!reset && dut.mem_out.fu_mem_done) begin
      $display("[%0t] FU MEM DONE : rob=%0d pd=%0d data=0x%08h",
               $time, dut.mem_out.rob_fu_mem, dut.mem_out.p_mem, dut.mem_out.data);
    end

    if (!reset && dut.b_out.fu_b_done) begin
      $display("[%0t] FU BR  DONE : rob=%0d pd=%0d mispredict=%0b tag=%0d jalr_bne=%0b pc=0x%08h",
               $time,
               dut.b_out.rob_fu_b,
               dut.b_out.p_b,
               dut.b_out.mispredict,
               dut.b_out.mispredict_tag,
               dut.b_out.jalr_bne_signal,
               dut.b_out.pc);
    end
  end

  // ---------------- Global mispredict monitor (with de-dup) ----------------
  logic [4:0] last_mispredict_tag;
  logic       seen_mispredict_for_tag;

  always_ff @(posedge clk) begin
    if (reset) begin
      last_mispredict_tag     <= '0;
      seen_mispredict_for_tag <= 1'b0;
    end else begin
      if (dut.mispredict) begin
        if (!seen_mispredict_for_tag || (dut.mispredict_tag != last_mispredict_tag)) begin
          $display("[%0t] *** GLOBAL MISPREDICT tag=%0d ***",
                   $time, dut.mispredict_tag);
          last_mispredict_tag     <= dut.mispredict_tag;
          seen_mispredict_for_tag <= 1'b1;
        end
        // If same tag repeats, we suppress extra prints to avoid spam
      end
    end
  end

endmodule
