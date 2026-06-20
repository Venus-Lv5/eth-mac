class reg_rw_test extends eth_base_test;
	`uvm_component_utils(reg_rw_test)

	uvm_reg_bit_bash_seq bit_bash_seq;

	function new(string name="reg_rw_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual task run_phase(uvm_phase phase);
		bit_bash_seq = uvm_reg_bit_bash_seq::type_id::create("bit_bash_seq");
		phase.raise_objection(this);
		bit_bash_seq.model = regmodel;
		uvm_resource_db#(bit)::set({"REG::", regmodel.TX_LEN.get_full_name()}, "NO_REG_BIT_BASH_TEST", 1, this);
		bit_bash_seq.start(null);
		phase.drop_objection(this);
	endtask
endclass
