// Synchronous FIFO with FIFO clear. 
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
  parameter int unsigned DATA_WIDTH = 8,       // RAM data width
  parameter int unsigned DEPTH = 16,           // Must be power of 2
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
  localparam int PTR_WIDTH = ADDR_WIDTH + 1;  // Extra bit for full/empty
    
  // Memory array
  logic [DATA_WIDTH-1:0] mem [DEPTH];
  
  // Read and write pointers with extra bit
  logic [PTR_WIDTH-1:0] wr_ptr, rd_ptr;

  // Output register
  logic [DATA_WIDTH-1:0] output_register;
  logic [DATA_WIDTH-1:0] rd_data;
  
  // Full and o_empty conditions
  assign o_full  = (wr_ptr[PTR_WIDTH-1] != rd_ptr[PTR_WIDTH-1]) && 
                 (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
  assign o_empty = (wr_ptr == rd_ptr);

  // Write logic
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
  
  // Read logic
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr <= '0;
    end else begin
      if (i_clr) begin
        rd_ptr <= '0;
      end else if (i_rd_en && !o_empty) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
    end
  end

  // FIFO write
  always_ff @(posedge clk) begin
    if (i_wr_en && !o_full && !i_clr) begin
      mem[wr_ptr[ADDR_WIDTH-1:0]] <= i_wr_data;
    end
  end
 
  // FIFO read
  // One-cycle latency: data appears the cycle after i_rd_en assertion
  always_ff @(posedge clk) begin
    if (i_rd_en && !o_empty) begin
      rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
    end
  end

  // If output register is enabled, this increases latency by additional 1 clock cycle, but
  // it significantly improves timing
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
