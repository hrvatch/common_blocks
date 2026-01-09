// Synchronous FIFO with FIFO clear - Optimized for timing
// FIFO depth MUST be a power of two.
//
// When 'i_rd_en' is asserted, data will appear on the output after 1 clock cycle, unless
// EXTRA_OUTPUT_REGISTER parameter is set; if that is the case, data will appear on the
// output in 2 clock cycles.
// 
// Other signals - 'o_empty', 'o_full', are updated as soon as the FIFO status changes.
// End user should take care of the read data latency handling.
//
// - The 'o_empty' signal is asserted when FIFO is empty.
// - The 'o_full' signal is asserted when FIFO is full.
// - Asserting 'i_clr' will empty the FIFO. Note - when 'i_clr' is asserted, if 'i_rd_en' was
//   asserted in the previous clock cycle, a read data will still appear on the output.
module sync_fifo_with_clear #(
  parameter int unsigned DATA_WIDTH = 32,       // RAM data width
  parameter int unsigned DEPTH = 1024,           // Must be power of 2
  parameter bit EXTRA_OUTPUT_REGISTER = 1'b0   // Adding output register increases latency to 2cc
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
  
  localparam int ADDR_WIDTH = $clog2(DEPTH);
  localparam int COUNT_WIDTH = $clog2(DEPTH+1);  // Can hold 0 to DEPTH
  
  // Memory array
  logic [DATA_WIDTH-1:0] mem [DEPTH];
  
  // Simple address counters (no extra MSB for full/empty detection)
  logic [ADDR_WIDTH-1:0] wr_addr, rd_addr;
  
  // Occupancy counter for full/empty detection
  logic [COUNT_WIDTH-1:0] count;
  
  // Output registers
  logic [DATA_WIDTH-1:0] output_register;
  logic [DATA_WIDTH-1:0] rd_data;
  
  // Full/empty based purely on counter (no pointer comparison!)
  logic internal_full, internal_empty;
  logic will_write, will_read;
  
  assign internal_full  = (count == DEPTH[COUNT_WIDTH-1:0]);
  assign internal_empty = (count == '0);
  
  assign o_full  = internal_full;
  assign o_empty = internal_empty;
  
  // Determine actual operations this cycle
  assign will_write = i_wr_en && !internal_full;
  assign will_read  = i_rd_en && !internal_empty;
  
  // Occupancy counter - INDEPENDENT of address logic
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
  
  // FIFO write - now uses counter-based full flag
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
  
  // FIFO read - power-efficient with read enable
  // One-cycle latency: data appears the cycle after i_rd_en assertion
  always_ff @(posedge clk) begin
    if (will_read) begin
      rd_data <= mem[rd_addr];
    end
  end
  
  // Optional extra output register for timing improvement
  generate
    if (EXTRA_OUTPUT_REGISTER) begin : ram_output_register
      always_ff @(posedge clk) begin
        output_register <= rd_data;
      end
      assign o_rd_data = output_register;
    end else begin
      assign o_rd_data = rd_data;
    end
  endgenerate
  
endmodule : sync_fifo_with_clear
