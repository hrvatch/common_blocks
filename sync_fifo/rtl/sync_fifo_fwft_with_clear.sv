// Synchronous FWFT (First Word Fall-Through) FIFO with clear
// FIFO depth MUST be a power of two.
//
// In FWFT mode:
// - Data is immediately available on 'o_rd_data' when 'o_empty' is deasserted
// - No read latency - data is always valid when !o_empty
// - 'i_rd_en' acknowledges consumption of current data and advances to next word
//
// Critical path is counter to the ram read_enable/write_enable
// Achieves ~303 MHz max frequency on XC7A200T , Speed grade -1

module sync_fifo_fwft_with_clear #(
  parameter int unsigned DATA_WIDTH = 8,
  parameter int unsigned DEPTH = 16,
  parameter bit EXTRA_OUTPUT_REGISTER = 1'b0
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  i_clr,
  
  input  logic                  i_wr_en,
  input  logic [DATA_WIDTH-1:0] i_wr_data,
  output logic                  o_full,
  
  input  logic                  i_rd_en,
  output logic [DATA_WIDTH-1:0] o_rd_data,
  output logic                  o_empty
);
  
  localparam int ADDR_WIDTH = $clog2(DEPTH);
  localparam int PTR_WIDTH = ADDR_WIDTH + 1;
  localparam int COUNT_WIDTH = $clog2(DEPTH+1); // Can hold 0 to DEPTH
  
  logic [DATA_WIDTH-1:0] mem [DEPTH];
  
  // Simple address counters (no MSB for full/empty detection)
  logic [ADDR_WIDTH-1:0] wr_addr, rd_addr;
  
  // Occupancy counter for full/empty detection
  logic [COUNT_WIDTH-1:0] count;
  
  logic [DATA_WIDTH-1:0] mem_rd_data;
  logic mem_rd_en;
  
  logic [DATA_WIDTH-1:0] bypass_data;
  logic use_bypass;
  
  logic internal_empty, internal_full;
  logic will_write, will_read;
  
  // Full/empty based purely on counter (no pointer comparison!)
  assign internal_full  = (count == DEPTH[COUNT_WIDTH-1:0]);
  assign internal_empty = (count == '0);
  
  assign o_empty = internal_empty;
  assign o_full  = internal_full;
  
  // Determine actual operations this cycle
  assign will_write = i_wr_en && !internal_full;
  assign will_read  = i_rd_en && !internal_empty;
  
  // Occupancy counter - INDEPENDENT of pointer logic
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      count <= '0;
    end else if (i_clr) begin
      count <= '0;
    end else begin
      case ({will_write, will_read})
        2'b10: count <= count + 1'b1;  // Write only
        2'b01: count <= count - 1'b1;  // Read only
        // 2'b11: count unchanged (simultaneous)
        // 2'b00: count unchanged (idle)
        default: count <= count;
      endcase
    end
  end
  
  // Write address counter
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_addr <= '0;
    end else if (i_clr) begin
      wr_addr <= '0;
    end else if (will_write) begin
      wr_addr <= wr_addr + 1'b1;
    end
  end
  
  // Memory write - uses counter-based full flag (FAST PATH!)
  always_ff @(posedge clk) begin
    if (will_write && !i_clr) begin
      mem[wr_addr] <= i_wr_data;
    end
  end
  
  // Read address counter
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_addr <= '0;
    end else if (i_clr) begin
      rd_addr <= '0;
    end else if (will_read) begin
      rd_addr <= rd_addr + 1'b1;
    end
  end
  
  // Pre-fetch address for FWFT
  logic [ADDR_WIDTH-1:0] next_rd_addr;
  assign next_rd_addr = rd_addr + 1'b1;
  
  // Memory read enable (bypass when writing to empty or simultaneous with count==1)
  assign mem_rd_en = will_read && !(i_wr_en && (internal_empty || count == 'd1));
  
  always_ff @(posedge clk) begin
    if (mem_rd_en) begin
      mem_rd_data <= mem[next_rd_addr];
    end
  end
  
  // Bypass control
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      use_bypass <= 1'b0;
    end else begin
      if (i_wr_en && internal_empty) begin
        use_bypass <= 1'b1;
        bypass_data <= i_wr_data;
      end 
      else if (i_wr_en && i_rd_en && count == 'd1) begin
        use_bypass <= 1'b1;
        bypass_data <= i_wr_data;
      end
      else if (will_read) begin
        use_bypass <= 1'b0;
      end
    end
  end
  
  generate
    if (EXTRA_OUTPUT_REGISTER) begin : extra_output_reg
      logic [DATA_WIDTH-1:0] output_register;
      logic [DATA_WIDTH-1:0] bypass_data_stage2;
      logic use_bypass_stage2;
      
      always_ff @(posedge clk) begin
        output_register <= mem_rd_data;
        bypass_data_stage2 <= bypass_data;
      end

      always_ff @(posedge clk) begin
        if (!rst_n) begin
          use_bypass_stage2 <= 1'b0; 
        end else begin
          use_bypass_stage2 <= use_bypass;
        end
      end
  
      assign o_rd_data = use_bypass_stage2 ? bypass_data_stage2 : output_register;
    end else begin
      assign o_rd_data = use_bypass ? bypass_data : mem_rd_data;
    end
  endgenerate
endmodule : sync_fifo_fwft_with_clear
