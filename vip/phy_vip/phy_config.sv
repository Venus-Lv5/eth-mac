class phy_config extends uvm_object;

	typedef enum int {
		TX   = 1,
		RX   = 2,
		FULL = 3
	} mode_enum;

	typedef enum bit {
		MII_100M = 0,
		MII_10M  = 1
	} freq_enum;

	rand mode_enum       mode;
	rand freq_enum       freq;

	rand int unsigned 	 coll_det_delay;
	rand int unsigned    pause_frame_delay;

	rand int unsigned clk_tp;
	rand bit clk_en;

	rand bit [47:0]			mac_addr;
	rand bit [47:0]			phy_addr;

	rand bit [63:0]			hash;

	rand bit 						bro;
	rand bit 						fil_en;
	rand bit 						pro;

	rand bit [15:0]			tx_len;

	constraint clk_period {
		soft clk_en == 1;
		if (freq == MII_100M) clk_tp == 40;
		if (freq == MII_10M)  clk_tp == 400;
	}

	constraint len_size {
		soft tx_len inside {[0:1500]};
	}

	`uvm_object_utils_begin(phy_config)
		`uvm_field_enum(mode_enum,        mode,              UVM_ALL_ON | UVM_BIN)
		`uvm_field_enum(freq_enum,        freq,              UVM_ALL_ON | UVM_BIN)
		`uvm_field_int (coll_det_delay,                      UVM_ALL_ON | UVM_DEC)
		`uvm_field_int (pause_frame_delay,                   UVM_ALL_ON | UVM_DEC)
		`uvm_field_int (clk_tp,                              UVM_ALL_ON | UVM_DEC)
		`uvm_field_int (clk_en,                              UVM_ALL_ON | UVM_BIN)
		`uvm_field_int (mac_addr,                            UVM_ALL_ON | UVM_HEX)
		`uvm_field_int (phy_addr,                            UVM_ALL_ON | UVM_HEX)
		`uvm_field_int (hash,                                UVM_ALL_ON | UVM_HEX)
		`uvm_field_int (bro,                                 UVM_ALL_ON | UVM_BIN)
		`uvm_field_int (fil_en,                              UVM_ALL_ON | UVM_BIN)
		`uvm_field_int (pro,                                 UVM_ALL_ON | UVM_BIN)
		`uvm_field_int (tx_len,                                 UVM_ALL_ON | UVM_DEC)
	`uvm_object_utils_end

  function new(string name="phy_config");
    super.new(name);

    
    mode        = FULL;
    freq        = MII_100M;

		coll_det_delay = 0;
		pause_frame_delay = 0;

		clk_tp = 40;
		clk_en = 1;

		mac_addr 	= 48'h11_22_33_44_55_66;
		phy_addr 	= 48'h01_80_c2_00_00_01;
		hash			= 0;
		pro				= 0;
		fil_en		= 0;
		bro				= 0;
		tx_len		= 46;
	endfunction: new



endclass: phy_config
