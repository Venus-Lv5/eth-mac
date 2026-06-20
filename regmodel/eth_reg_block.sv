class eth_reg_block extends uvm_reg_block;
  `uvm_object_utils(eth_reg_block)

  rand eth_MAC_SA_LOW_reg  MAC_SA_LOW;
  rand eth_MAC_SA_HIGH_reg MAC_SA_HIGH;
  rand eth_PAUSE_CTRL_reg  PAUSE_CTRL;
  rand eth_IER_reg         IER;
  rand eth_MAC_CTRL_reg    MAC_CTRL;
  rand eth_HASH_0_reg      HASH_0;
  rand eth_HASH_1_reg      HASH_1;
  rand eth_TX_DA_LOW_reg   TX_DA_LOW;
  rand eth_TX_DA_HIGH_reg  TX_DA_HIGH;
  rand eth_TX_LEN_reg      TX_LEN;
  rand eth_TX_DATA_reg     TX_DATA;
  rand eth_TX_CMD_reg      TX_CMD;
  rand eth_FSR_reg         FSR;
  rand eth_RX_LEN_reg      RX_LEN;
  rand eth_RX_DATA_reg     RX_DATA;
  rand eth_RX_CMD_reg      RX_CMD;

  uvm_reg_map ahb_map;

  function new(string name="eth_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    MAC_SA_LOW = eth_MAC_SA_LOW_reg::type_id::create("MAC_SA_LOW");
    MAC_SA_LOW.configure(this);
    MAC_SA_LOW.build();

    MAC_SA_HIGH = eth_MAC_SA_HIGH_reg::type_id::create("MAC_SA_HIGH");
    MAC_SA_HIGH.configure(this);
    MAC_SA_HIGH.build();

    PAUSE_CTRL = eth_PAUSE_CTRL_reg::type_id::create("PAUSE_CTRL");
    PAUSE_CTRL.configure(this);
    PAUSE_CTRL.build();

    IER = eth_IER_reg::type_id::create("IER");
    IER.configure(this);
    IER.build();

    MAC_CTRL = eth_MAC_CTRL_reg::type_id::create("MAC_CTRL");
    MAC_CTRL.configure(this);
    MAC_CTRL.build();

    HASH_0 = eth_HASH_0_reg::type_id::create("HASH_0");
    HASH_0.configure(this);
    HASH_0.build();

    HASH_1 = eth_HASH_1_reg::type_id::create("HASH_1");
    HASH_1.configure(this);
    HASH_1.build();

    TX_DA_LOW = eth_TX_DA_LOW_reg::type_id::create("TX_DA_LOW");
    TX_DA_LOW.configure(this);
    TX_DA_LOW.build();

    TX_DA_HIGH = eth_TX_DA_HIGH_reg::type_id::create("TX_DA_HIGH");
    TX_DA_HIGH.configure(this);
    TX_DA_HIGH.build();

    TX_LEN = eth_TX_LEN_reg::type_id::create("TX_LEN");
    TX_LEN.configure(this);
    TX_LEN.build();

    TX_DATA = eth_TX_DATA_reg::type_id::create("TX_DATA");
    TX_DATA.configure(this);
    TX_DATA.build();

    TX_CMD = eth_TX_CMD_reg::type_id::create("TX_CMD");
    TX_CMD.configure(this);
    TX_CMD.build();

    FSR = eth_FSR_reg::type_id::create("FSR");
    FSR.configure(this);
    FSR.build();

    RX_LEN = eth_RX_LEN_reg::type_id::create("RX_LEN");
    RX_LEN.configure(this);
    RX_LEN.build();

    RX_DATA = eth_RX_DATA_reg::type_id::create("RX_DATA");
    RX_DATA.configure(this);
    RX_DATA.build();

    RX_CMD = eth_RX_CMD_reg::type_id::create("RX_CMD");
    RX_CMD.configure(this);
    RX_CMD.build();

    ahb_map = create_map("ahb_map", 0, 4, UVM_LITTLE_ENDIAN);

    ahb_map.add_reg(MAC_SA_LOW,  `UVM_REG_ADDR_WIDTH'h00, "RW");
    ahb_map.add_reg(MAC_SA_HIGH, `UVM_REG_ADDR_WIDTH'h04, "RW");
    ahb_map.add_reg(PAUSE_CTRL,  `UVM_REG_ADDR_WIDTH'h08, "RW");
    ahb_map.add_reg(IER,         `UVM_REG_ADDR_WIDTH'h0C, "RW");
    ahb_map.add_reg(MAC_CTRL,    `UVM_REG_ADDR_WIDTH'h10, "RW");
    ahb_map.add_reg(HASH_0,      `UVM_REG_ADDR_WIDTH'h20, "RW");
    ahb_map.add_reg(HASH_1,      `UVM_REG_ADDR_WIDTH'h24, "RW");
    ahb_map.add_reg(TX_DA_LOW,   `UVM_REG_ADDR_WIDTH'h40, "RW");
    ahb_map.add_reg(TX_DA_HIGH,  `UVM_REG_ADDR_WIDTH'h44, "RW");
    ahb_map.add_reg(TX_LEN,      `UVM_REG_ADDR_WIDTH'h48, "RW");
    ahb_map.add_reg(TX_DATA,     `UVM_REG_ADDR_WIDTH'h4C, "WO");
    ahb_map.add_reg(TX_CMD,      `UVM_REG_ADDR_WIDTH'h50, "WO");
    ahb_map.add_reg(FSR,         `UVM_REG_ADDR_WIDTH'h60, "RW");
    ahb_map.add_reg(RX_LEN,      `UVM_REG_ADDR_WIDTH'h64, "RO");
    ahb_map.add_reg(RX_DATA,     `UVM_REG_ADDR_WIDTH'h68, "RO");
    ahb_map.add_reg(RX_CMD,      `UVM_REG_ADDR_WIDTH'h6C, "WO");

    lock_model();
  endfunction
endclass

