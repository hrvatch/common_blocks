module sync_fifo_fwft_with_clear_formal_tb #(
  parameter int unsigned DATA_WIDTH = 8,
  parameter int unsigned DEPTH = 8,
  parameter int unsigned EXTRA_OUTPUT_REGISTER = 1'b0
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  i_clr,

  // Write interface
  input  logic                  i_wr_en,
  input  logic [DATA_WIDTH-1:0] i_wr_data,
  output logic                  o_full,
  
  // Read interface
  input  logic                  i_rd_en,
  output logic [DATA_WIDTH-1:0] o_rd_data,
  output logic                  o_empty
);

  // Default clock and reset to reduce typing
  default clocking cb @(posedge clk);
  endclocking

  default disable iff (!rst_n);

  // Some assertions that are absoulutely low hanging fruit
  asrt_no_empty_full_at_the_same_time : assert property(!(o_empty && o_full));
  asrt_clr_empty : assert property (i_clr |=> o_empty);
  
  // Corner case: FIFO is full and both i_wr_en and i_rd_en are asserted. What should happen?
  // Well, we can't write to the FIFO when it's full, therefore only read can be performed, and
  // we assert overflow.
  //
  // Corner case: FIFO is empty and both i_wr_en and i_rd_en are asserted. What should happen?
  // Well, we can't read from an empty FIFO, therefore only write can be performed, and
  // we assert underflow.

  // Auxilliary logic, it's going to be similar to the FIFO logic
  int sample_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_count <= '0;
    end else begin
      if (i_clr) begin
        sample_count <= '0;
      end else begin
        if (((sample_count == 0) && i_wr_en) || 
            (i_wr_en && sample_count > 0 && sample_count < DEPTH && !i_rd_en)) begin
          sample_count <= sample_count + 1;
        end

        if (((sample_count == DEPTH) && i_rd_en) || 
            (!i_wr_en && sample_count > 0 && sample_count < DEPTH && i_rd_en)) begin
          sample_count <= sample_count - 1;
        end
      end
    end
  end

  asrt_full : assert property (sample_count == DEPTH |-> o_full);
  asrt_empty : assert property (sample_count  == 0 |-> o_empty);

  // === Jasper Scoreboard ===
  // We need delayed version of read data for the Jasper Scoreboard
  logic rd_en_stage1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_en_stage1 <= 1'b0;
    end else begin
      rd_en_stage1 <= i_rd_en & ~o_empty & ~i_clr;
    end
  end

  logic scbd_rst_n;
  assign scbd_rst_n = rst_n & ~i_clr;
  generate
    if (EXTRA_OUTPUT_REGISTER) begin : extra_output_register
      jasper_scoreboard_3 #(
        .CHUNK_WIDTH(DATA_WIDTH),
        .IN_CHUNKS(1),
        .OUT_CHUNKS(1),
        .ORDERING(`JS3_IN_ORDER),
        .SINGLE_CLOCK(1),
        .MAX_PENDING(DEPTH),
        .FREE_DATA(1)
      ) scoreboard (
        .clk(clk), 
        .rstN(scbd_rst_n),
        .incoming_vld(i_wr_en & ~o_full),
        .incoming_data(i_wr_data),
        .outgoing_vld(rd_en_stage1),
        .outgoing_data(o_rd_data)
      );
    end else begin : no_extra_output_register
      jasper_scoreboard_3 #(
        .CHUNK_WIDTH(DATA_WIDTH),
        .IN_CHUNKS(1),
        .OUT_CHUNKS(1),
        .ORDERING(`JS3_IN_ORDER),
        .SINGLE_CLOCK(1) ,
        .MAX_PENDING(DEPTH),
        .FREE_DATA(1)
      ) scoreboard (
        .clk(clk), 
        .rstN(scbd_rst_n),
        .incoming_vld(i_wr_en & ~o_full),
        .incoming_data(i_wr_data),
        .outgoing_vld(i_rd_en & ~o_empty),
        .outgoing_data(o_rd_data)
      );
    end
  endgenerate


  // === Covers ===
  // Cover FIFO going from empty to full to empty
  cov_fifo_empty_full_empty : cover property ((i_clr == 0)[*1:$] intersect (o_empty ##[0:$] o_full ##[0:$] o_empty));
 
  // DUT instance
  sync_fifo_fwft_with_clear #(
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH (DEPTH),
    .EXTRA_OUTPUT_REGISTER (EXTRA_OUTPUT_REGISTER)
  ) dut (
    .clk (clk),
    .rst_n (rst_n),
    .i_clr (i_clr),
    .i_wr_en (i_wr_en),
    .i_wr_data (i_wr_data),
    .o_full (o_full),
    .i_rd_en (i_rd_en),
    .o_rd_data (o_rd_data),
    .o_empty (o_empty)
  );

endmodule : sync_fifo_fwft_with_clear_formal_tb
