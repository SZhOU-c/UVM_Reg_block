`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_transaction extends uvm_sequence_item;
  
  rand bit wr_en;
  rand bit rd_en;
  rand bit [3:0] addr;
  rand bit [7:0] wdata;
  bit [7:0] rdata;
  
  constraint wr_xor_rd_c {
   wr_en != rd_en; 
  }
  
  `uvm_object_utils_begin(reg_transaction)
    `uvm_field_int(wr_en,  UVM_ALL_ON)
    `uvm_field_int(rd_en,  UVM_ALL_ON)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(wdata,  UVM_ALL_ON)
    `uvm_field_int(rdata,  UVM_ALL_ON)
  `uvm_object_utils_end
  
  function new(string name = "reg_transaction");
    super.new(name);
  endfunction
  
endclass
  

class reg_driver extends uvm_driver #(reg_transaction);
  
  `uvm_component_utils(reg_driver)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
	
  virtual reg_if vif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( ! uvm_config_db #(virtual reg_if):: get(this, "", "vif", vif) ) begin
      `uvm_fatal(get_type_name(), "Didn't get to handle to virtual interface reg_if")
    end
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    
    reg_transaction tr;
    
    forever begin
      
      seq_item_port.get_next_item(tr);
      
      @(posedge vif.clk);
      vif.wr_en <= tr.wr_en;
      vif.rd_en <= tr.rd_en;
      vif.addr <= tr.addr;
      vif.wdata <= tr.wdata;
      // second posedge is always necessary because calling the item done immediately changes the input
      // we want to make suer DUT acutally sees it
      @(posedge vif.clk);
      
      if(tr.rd_en) begin
        @(posedge vif.clk);
        tr.rdata <= vif.rdata;
      end
      
      seq_item_port.item_done();
    end
  endtask
  
  
endclass


class reg_monitor extends uvm_monitor;
  
  `uvm_component_utils(reg_monitor)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  
  virtual reg_if vif;
  
  uvm_analysis_port #(reg_transaction) mon_analysis_port;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    mon_analysis_port = new("mon_analysis_port", this);
    
    if(!uvm_config_db #(virtual reg_if) :: get(this, "", "vif", vif) )begin
      `uvm_error(get_type_name(), "Didn't get to handle virtual interface reg_if");
    end
    
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    reg_transaction tr;
    
    forever begin
      @(posedge vif.clk);
      
      if(vif.wr_en) begin
        tr = reg_transaction::type_id::create("tr", this);
        tr.wr_en = 1;
        tr.addr = vif.addr;
        tr.wdata = vif.wdata;
        mon_analysis_port.write(tr);
      end
      else if(vif.rd_en) begin
        tr = reg_transaction::type_id::create("tr", this);
        tr.rd_en = 1;
        tr.addr = vif.addr;
        
        @(posedge vif.clk);
        tr.rdata = vif.rdata;
        
        mon_analysis_port.write(tr);
      end
    end
  endtask
  
  
  
endclass

class reg_coverage extends uvm_subscriber #(reg_transaction);
  
  `uvm_component_utils(reg_coverage)
  
  covergroup cg_reg_transaction;
    coverpoint trans.addr;
    coverpoint trans.wr_en;
  endgroup
  
  reg_transaction trans;
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_reg_transaction = new();
  endfunction
  
  virtual function void write(reg_transaction t);
    trans = t;
    cg_reg_transaction.sample();
  endfunction
  

  
endclass
    
class reg_sequencer extends uvm_sequencer #(reg_transaction);
  
  `uvm_component_utils(reg_sequencer)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  
  // seq.start() ?
  
  
endclass

class reg_sequence extends uvm_sequence #(reg_transaction);
  
  `uvm_object_utils(reg_sequence)
  
  function new(string name = "reg_sequence");
    super.new(name);
  endfunction
  
  virtual task pre_body();
    uvm_phase starting_phase = get_starting_phase();
    if(starting_phase != null)
      starting_phase.raise_objection(this);
  endtask
  
  virtual task body();
    repeat (5) begin
      req = reg_transaction::type_id::create("req");
      start_item(req);
      assert(req.randomize());
      finish_item(req);
    end
    
  endtask
  
  virtual task post_body();
    uvm_phase starting_phase = get_starting_phase();
    if(starting_phase != null)
      starting_phase.drop_objection(this);
  endtask
      
  
endclass

class reg_scoreboard extends uvm_scoreboard;
  
  `uvm_component_utils(reg_scoreboard)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  uvm_analysis_imp #(reg_transaction, reg_scoreboard) ap_imp;
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction
  
  bit [7:0] expected_mem [16];
  
  bit written [16];
  
  virtual function void write(reg_transaction tr);
    if(tr.wr_en) begin
      expected_mem[tr.addr] = tr.wdata;
      written[tr.addr]		= 1;
    end
    else if (tr.rd_en) begin
      if(!written[tr.addr]) begin
        `uvm_info(get_type_name(), $sformatf("addr=%0d read before any write, skipping check", tr.addr), UVM_LOW)
      end
      else if( tr.rdata != expected_mem[tr.addr] ) begin
        `uvm_error(get_type_name(), $sformatf("Mismatch at addr=%0d: expected=0x%0h actual=0x%0h", tr.addr, expected_mem[tr.addr], tr.rdata))
      end
      else begin
      `uvm_info(get_type_name(), $sformatf("addr=%0d matched: 0x%0h", tr.addr, tr.rdata), UVM_HIGH)
      end
    end
    
  endfunction
      
  
endclass


class reg_agent extends uvm_agent;
  
  `uvm_component_utils(reg_agent)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  
  reg_driver m_driver;
  reg_monitor m_monitor;
  reg_sequencer m_sequencer;
  reg_coverage m_coverage;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (get_is_active()) begin
      m_sequencer = reg_sequencer::type_id::create("m_sequencer", this);
      m_driver	  = reg_driver::type_id::create("m_driver", this);
    end
    
    m_monitor  = reg_monitor::type_id::create("m_monitor", this);
    m_coverage = reg_coverage::type_id::create("m_coverage", this);
  endfunction
    
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    if(get_is_active()) 
      m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
    
    m_monitor.mon_analysis_port.connect(m_coverage.analysis_export);
    
  endfunction
  
endclass
  
class reg_env extends uvm_env;
    
  `uvm_component_utils(reg_env)
    
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  
  reg_agent m_agent;
  reg_scoreboard	m_scoreboard;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    m_agent = reg_agent::type_id::create("m_agent",this);
    m_scoreboard = reg_scoreboard::type_id::create("m_scoreboard",this);
    
  endfunction
  
  virtual function void connect_phase(uvm_phase phase );
    super.connect_phase(phase);
    
    m_agent.m_monitor.mon_analysis_port.connect(m_scoreboard.ap_imp);
  endfunction

    
  
endclass


class reg_test extends uvm_test;
  
  `uvm_component_utils(reg_test)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  
  reg_env m_top_env;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    m_top_env = reg_env::type_id::create("m_top_env", this);
  endfunction
  
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    reg_sequence m_seq = reg_sequence::type_id::create("m_seq", this);
    
    phase.raise_objection(this);
    m_seq.start(m_top_env.m_agent.m_sequencer);
    phase.drop_objection(this);
  endtask
  
  
endclass


module tb_top;
  
  bit clk;
  always #10 clk = ~clk;

  reg_if   reg_if0 (clk);
  reg_block dut0   (reg_if0);

  initial begin
    uvm_config_db #(virtual reg_if)::set(null, "uvm_test_top.m_top_env.m_agent.*", "vif", reg_if0);
    run_test("reg_test");
  end
  
endmodule


