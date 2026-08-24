interface reg_if (input bit clk);
  logic        rst_n;
  logic        wr_en;
  logic        rd_en;
  logic [3:0]  addr;
  logic [7:0]  wdata;
  logic [7:0]  rdata;
endinterface

module reg_block (reg_if vif);

  logic [7:0] mem [0:15];

  always @(posedge vif.clk or negedge vif.rst_n) begin
    if (!vif.rst_n) begin
      vif.rdata <= 8'h00;
    end
    else begin
      if (vif.wr_en) begin
        mem[vif.addr] <= vif.wdata;
      end
      else if (vif.rd_en) begin
        vif.rdata <= mem[vif.addr];
      end
    end
  end

endmodule
