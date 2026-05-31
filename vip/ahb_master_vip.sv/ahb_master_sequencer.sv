class ahb_master_sequencer extends uvm_sequencer #(ahb_master_transaction);
  `uvm_component_utils(ahb_master_sequencer)

  local string msg = "[AHB_MASTER_VIP][AHB_MASTER_SEQUENCER]";  

  function new(string name="ahb_master_sequencer", uvm_component parent);
    super.new(name,parent);
  endfunction: new

endclass: ahb_master_sequencer