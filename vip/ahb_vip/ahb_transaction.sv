class ahb_transaction extends uvm_sequence_item;
  typedef enum bit {
       WRITE = 1
      ,READ  = 0
  } xact_type_enum;

  typedef enum bit[2:0] {
    HSIZE_BYTE     = 3'b000
   ,HSIZE_HALFWORD = 3'b001
   ,HSIZE_WORD     = 3'b010
   ,HSIZE_DWORD    = 3'b011
   ,HSIZE_4WORD    = 3'b100
   ,HSIZE_8WORD    = 3'b101
   ,HSIZE_16WORD   = 3'b110
   ,HSIZE_32WORD   = 3'b111
  } hsize_e;
  
  typedef enum bit[2:0] {
    HBURST_SINGLE = 3'b000
   ,HBURST_INCR   = 3'b001
   ,HBURST_WRAP4  = 3'b010
   ,HBURST_INCR4  = 3'b011
   ,HBURST_WRAP8  = 3'b100
   ,HBURST_INCR8  = 3'b101
   ,HBURST_WRAP16 = 3'b110
   ,HBURST_INCR16 = 3'b111
  } hburst_e;

  typedef enum bit[1:0] {
    HTRANS_IDLE   = 2'b00
   ,HTRANS_BUSY   = 2'b01
   ,HTRANS_NONSEQ = 2'b10
   ,HTRANS_SEQ    = 2'b11
  } htrans_e;

  typedef enum bit {
    HRESP_OKAY  = 1'b0
   ,HRESP_ERROR = 1'b1
  } hresp_e;

  typedef hsize_e  xfer_size_enum;
  typedef hburst_e burst_type_enum;

  localparam hsize_e  SIZE_8BIT    = HSIZE_BYTE;
  localparam hsize_e  SIZE_16BIT   = HSIZE_HALFWORD;
  localparam hsize_e  SIZE_32BIT   = HSIZE_WORD;
  localparam hsize_e  SIZE_64BIT   = HSIZE_DWORD;
  localparam hsize_e  SIZE_128BIT  = HSIZE_4WORD;
  localparam hsize_e  SIZE_256BIT  = HSIZE_8WORD;
  localparam hsize_e  SIZE_512BIT  = HSIZE_16WORD;
  localparam hsize_e  SIZE_1024BIT = HSIZE_32WORD;
  localparam hburst_e SINGLE       = HBURST_SINGLE;
  localparam hburst_e INCR         = HBURST_INCR;
  localparam hburst_e WRAP4        = HBURST_WRAP4;
  localparam hburst_e INCR4        = HBURST_INCR4;
  localparam hburst_e WRAP8        = HBURST_WRAP8;
  localparam hburst_e INCR8        = HBURST_INCR8;
  localparam hburst_e WRAP16       = HBURST_WRAP16;
  localparam hburst_e INCR16       = HBURST_INCR16;

  rand bit[`AHB_ADDR_WIDTH-1:0] addr;
  rand bit[`AHB_DATA_WIDTH-1:0] data;
  rand bit                       write;
  rand bit[`AHB_DATA_WIDTH-1:0] wdata;
  bit[`AHB_DATA_WIDTH-1:0]      rdata;
  rand xact_type_enum           xact_type;
  rand hsize_e                  xfer_size;
  rand hburst_e                 burst_type;
  rand hsize_e                  size;
  rand hburst_e                 burst;
  rand bit[3:0]                 prot;
  bit                           lock;
  hresp_e                       resp;

  rand int unsigned             num_beats;
  rand int unsigned             idle_cycles;
  rand bit[`AHB_ADDR_WIDTH-1:0] addr_q[$];
  rand bit[`AHB_DATA_WIDTH-1:0] wdata_q[$];
  bit[`AHB_DATA_WIDTH-1:0]      rdata_q[$];
  hresp_e                       resp_q[$];
  htrans_e                      htrans;
  rand htrans_e                 trans;
  rand bit[`AHB_ADDR_WIDTH-1:0] beat_addr[$];
  rand bit[`AHB_DATA_WIDTH-1:0] beat_wdata[$];
  bit[`AHB_DATA_WIDTH-1:0]      beat_rdata[$];
  hresp_e                       beat_resp[$];
  int unsigned                  beat_index;

  `uvm_object_utils_begin (ahb_transaction)
    `uvm_field_enum       (xact_type_enum  ,xact_type   ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (hsize_e         ,xfer_size   ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (hburst_e        ,burst_type  ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (addr                         ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (data                         ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (write                        ,UVM_ALL_ON |UVM_DEC )
    `uvm_field_int        (wdata                        ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (rdata                        ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (hsize_e         ,size        ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (hburst_e        ,burst       ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (prot                         ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (lock                         ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (hresp_e         ,resp        ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (num_beats                    ,UVM_ALL_ON |UVM_DEC )
    `uvm_field_int        (idle_cycles                  ,UVM_ALL_ON |UVM_DEC )
    `uvm_field_queue_int  (addr_q                       ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_int  (wdata_q                      ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_int  (rdata_q                      ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_enum (hresp_e         ,resp_q      ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (htrans_e        ,htrans      ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_enum       (htrans_e        ,trans       ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_int  (beat_addr                    ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_int  (beat_wdata                   ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_int  (beat_rdata                   ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_queue_enum (hresp_e         ,beat_resp   ,UVM_ALL_ON |UVM_HEX )
    `uvm_field_int        (beat_index                   ,UVM_ALL_ON |UVM_DEC )
  `uvm_object_utils_end

  function new(string name="ahb_transaction");
    super.new(name);
    addr        = '0;
    data        = '0;
    write       = 1'b0;
    wdata       = '0;
    rdata       = '0;
    xact_type   = READ;
    xfer_size   = HSIZE_WORD;
    burst_type  = HBURST_SINGLE;
    size        = HSIZE_WORD;
    burst       = HBURST_SINGLE;
    prot        = 4'h0;
    lock        = 1'b0;
    resp        = HRESP_OKAY;
    num_beats   = 0;
    idle_cycles = 0;
    htrans      = HTRANS_NONSEQ;
    trans       = HTRANS_NONSEQ;
    beat_index  = 0;
  endfunction: new

  function void apply_compat_fields();
    if (write)
      xact_type = WRITE;
    else
      write = (xact_type == WRITE);

    if ((wdata != '0) && (data == '0))
      data = wdata;
    wdata = data;

    if (size != HSIZE_WORD)
      xfer_size = size;
    else
      size = xfer_size;

    if (burst != HBURST_SINGLE)
      burst_type = burst;
    else
      burst = burst_type;

    if (trans != HTRANS_NONSEQ)
      htrans = trans;
    else
      trans = htrans;

    if ((beat_addr.size() != 0) && (addr_q.size() == 0))
      addr_q = beat_addr;
    else if (addr_q.size() != 0)
      beat_addr = addr_q;

    if ((beat_wdata.size() != 0) && (wdata_q.size() == 0))
      wdata_q = beat_wdata;
    else if (wdata_q.size() != 0)
      beat_wdata = wdata_q;

    if ((beat_rdata.size() != 0) && (rdata_q.size() == 0))
      rdata_q = beat_rdata;
    else if (rdata_q.size() != 0)
      beat_rdata = rdata_q;

    if ((beat_resp.size() != 0) && (resp_q.size() == 0))
      resp_q = beat_resp;
    else if (resp_q.size() != 0)
      beat_resp = resp_q;
  endfunction: apply_compat_fields

  function void update_compat_fields();
    write = (xact_type == WRITE);
    wdata = data;
    size  = xfer_size;
    burst = burst_type;
    trans = htrans;

    if (rdata_q.size() != 0)
      rdata = rdata_q[0];
    beat_addr  = addr_q;
    beat_wdata = wdata_q;
    beat_rdata = rdata_q;
    beat_resp  = resp_q;
  endfunction: update_compat_fields

  function int unsigned get_xfer_bytes();
    return (1 << xfer_size);
  endfunction: get_xfer_bytes

  function int unsigned get_burst_len();
    if (num_beats != 0)
      return num_beats;
    if (beat_addr.size() != 0)
      return beat_addr.size();
    if (addr_q.size() != 0)
      return addr_q.size();
    if ((xact_type == WRITE) && (beat_wdata.size() != 0))
      return beat_wdata.size();
    if ((xact_type == WRITE) && (wdata_q.size() != 0))
      return wdata_q.size();

    case (burst_type)
      HBURST_SINGLE: return 1;
      HBURST_INCR:   return 1;
      HBURST_WRAP4,
      HBURST_INCR4:  return 4;
      HBURST_WRAP8,
      HBURST_INCR8:  return 8;
      HBURST_WRAP16,
      HBURST_INCR16: return 16;
      default:       return 1;
    endcase
  endfunction: get_burst_len

  function bit is_wrap_burst();
    return (burst_type == HBURST_WRAP4) || (burst_type == HBURST_WRAP8) || (burst_type == HBURST_WRAP16);
  endfunction: is_wrap_burst

  function bit[`AHB_ADDR_WIDTH-1:0] get_beat_addr(int unsigned beat);
    int unsigned bytes;
    int unsigned burst_len;
    int unsigned wrap_bytes;
    int unsigned wrap_base;
    int unsigned next_addr;
    bit[`AHB_ADDR_WIDTH-1:0] calc_addr;

    if (beat_addr.size() > beat)
      return beat_addr[beat];
    if (addr_q.size() > beat)
      return addr_q[beat];

    bytes = get_xfer_bytes();
    burst_len = get_burst_len();
    next_addr = addr + (beat * bytes);

    if (is_wrap_burst() && (burst_len != 0)) begin
      wrap_bytes = burst_len * bytes;
      wrap_base  = (addr / wrap_bytes) * wrap_bytes;
      next_addr  = wrap_base + ((next_addr - wrap_base) % wrap_bytes);
    end

    calc_addr = next_addr;
    return calc_addr;
  endfunction: get_beat_addr

  function bit[`AHB_DATA_WIDTH-1:0] get_beat_wdata(int unsigned beat);
    if (beat_wdata.size() > beat)
      return beat_wdata[beat];
    if (wdata_q.size() > beat)
      return wdata_q[beat];
    return data;
  endfunction: get_beat_wdata

  function bit is_aligned();
    int unsigned bytes;
    bytes = get_xfer_bytes();
    if (bytes == 0)
      return 0;
    for (int unsigned ii = 0; ii < get_burst_len(); ii++) begin
      if ((get_beat_addr(ii) % bytes) != 0)
        return 0;
    end
    return 1;
  endfunction: is_aligned

  virtual function string convert2string();
    string str;
    str = $sformatf("%s addr=0x%0h data=0x%0h size=%0s burst=%0s beats=%0d prot=0x%0h lock=%0b resp=%0b",
                    xact_type.name(), addr, data, xfer_size.name(), burst_type.name(),
                    get_burst_len(), prot, lock, resp);
    if (get_burst_len() > 1) begin
      for (int unsigned ii = 0; ii < get_burst_len(); ii++) begin
        str = {str, $sformatf("\n  beat[%0d] addr=0x%0h wdata=0x%0h rdata=0x%0h resp=%0b",
                              ii, get_beat_addr(ii), get_beat_wdata(ii),
                              (rdata_q.size() > ii) ? rdata_q[ii] : '0,
                              (resp_q.size() > ii) ? resp_q[ii] : 1'b0)};
      end
    end
    return str;
  endfunction: convert2string

endclass: ahb_transaction
