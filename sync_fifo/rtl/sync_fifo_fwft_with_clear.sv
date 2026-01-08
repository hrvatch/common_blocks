// Synchronous FWFT (First Word Fall-Through) FIFO with clear
// FIFO depth MUST be a power of two.
//
// In FWFT mode:
// - Data is immediately available on 'o_rd_data' when 'o_empty' is deasserted
// - No read latency - data is always valid when !o_empty
// - 'i_rd_en' acknowledges consumption of current data and advances to next word
// - Effective capacity is DEPTH (internal memory) + 1 (output register)
module sync_fifo_fwft_with_clear #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned DEPTH = 1024,
  parameter bit EXTRA_OUTPUT_REGISTER = 1'b0
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  i_clr,
  
  // Write interface
  input  logic                  i_wr_en,
  input  logic [DATA_WIDTH-1:0] i_wr_data,
  output logic                  o_full,
  
  // Read interface - FWFT: data valid when !o_empty
  input  logic                  i_rd_en,
  output logic [DATA_WIDTH-1:0] o_rd_data,
  output logic                  o_empty
);
  
  localparam int ADDR_WIDTH = $clog2(DEPTH);
  localparam int PTR_WIDTH = ADDR_WIDTH + 1;
  
  // Internal FIFO memory
  logic [DATA_WIDTH-1:0] mem [DEPTH];
  
  // Internal FIFO pointers
  logic [PTR_WIDTH-1:0] wr_ptr, rd_ptr, ptr_dist;

  // Read address and data for BRAM
  logic [ADDR_WIDTH-1:0] rd_addr;
  logic [DATA_WIDTH-1:0] mem_rd_data;
  logic mem_rd_en;
  
  // FWFT output and bypass control
  logic [DATA_WIDTH-1:0] output_data;
  logic use_bypass;
  logic [DATA_WIDTH-1:0] bypass_data;
  
  // Internal FIFO status
  logic internal_empty, internal_full;
  
  assign internal_full  = (wr_ptr[PTR_WIDTH-1] != rd_ptr[PTR_WIDTH-1]) && 
                          (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
  assign internal_empty = (wr_ptr == rd_ptr);
  assign ptr_dist = wr_ptr - rd_ptr;
  
  // External interface
  assign o_empty   = internal_empty;
  assign o_full    = internal_full;
  
  // Write pointer logic (unchanged)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else begin
      if (i_clr) begin
        wr_ptr <= '0;
      end else if (i_wr_en && !o_full) begin
        wr_ptr <= wr_ptr + 1'b1;
      end
    end
  end
  
  // Internal FIFO write (unchanged)
  always_ff @(posedge clk) begin
    if (i_wr_en && !o_full && !i_clr) begin
      mem[wr_ptr[ADDR_WIDTH-1:0]] <= i_wr_data;
    end
  end
  
  // Read pointer logic - advances when fetching next word
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr <= '0;
    end else begin
      if (i_clr) begin
        rd_ptr <= '0;
      end else if (i_rd_en && !internal_empty) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
    end
  end
 
  // Read address calculation (pre-fetch next word for FWFT)
  logic [ADDR_WIDTH-1:0] next_rd_addr;
  assign next_rd_addr = rd_ptr[ADDR_WIDTH-1:0] + 1'b1;

  // Memory read enable - only read when NOT bypassing
  // Bypass occurs when: (1) writing to empty, or (2) simultaneous wr/rd with ptr_dist==1
  assign mem_rd_en = i_rd_en && !internal_empty && (!i_wr_en || ptr_dist != 'd1);
  
  // Memory read with enable (POWER EFFICIENT + BRAM inference)
  always_ff @(posedge clk) begin
    if (mem_rd_en) begin
      mem_rd_data <= mem[next_rd_addr];
    end
  end
  
  // Bypass control logic
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      use_bypass <= 1'b0;
    end else begin
      if (i_wr_en && internal_empty) begin
        use_bypass <= 1'b1;
        bypass_data <= i_wr_data;
      end 
      else if (i_wr_en && i_rd_en && ptr_dist == 'd1) begin
        use_bypass <= 1'b1;
        bypass_data <= i_wr_data;
      end
      else if (i_rd_en && !internal_empty) begin
        use_bypass <= 1'b0;
      end
    end
  end
  
  // Optional extra output register for DATA ONLY
  generate
    if (EXTRA_OUTPUT_REGISTER) begin : extra_output_reg
      logic [DATA_WIDTH-1:0] output_register;
      logic [DATA_WIDTH-1:0] bypass_data_stage2;
      logic use_bypass_stage2;
      
      always_ff @(posedge clk) begin
        output_register <= mem_rd_data;
      end

      always_ff @(posedge clk) begin
        bypass_data_stage2 <= bypass_data;
      end

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          use_bypass_stage2 <= 1'b0; 
        end else begin
          use_bypass_stage2 <= use_bypass;
        end
      end
  
      // Output mux: select between bypass and memory
      assign o_rd_data = use_bypass_stage2 ? bypass_data_stage2 : output_register;
    end else begin
      assign o_rd_data = use_bypass ? bypass_data : mem_rd_data;
    end
  endgenerate
endmodule : sync_fifo_fwft_with_clear
