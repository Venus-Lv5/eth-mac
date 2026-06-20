class phy_sequencer extends uvm_sequencer #(phy_transaction);
  `uvm_component_utils(phy_sequencer)

  local string msg = "[PHY_VIP][PHY_SEQUENCER]";  

  function new(string name="phy_sequencer", uvm_component parent);
    super.new(name,parent);
  endfunction: new

endclass: phy_sequencer