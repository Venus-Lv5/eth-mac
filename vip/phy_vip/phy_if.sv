interface phy_if();

  // TX
  logic                   TX_CLK;
  logic [3:0]             TXD;
  logic                   TX_EN;
  logic                   TX_ERR;

  // RX
  logic                   RX_CLK;
  logic [3:0]             RXD;
  logic                   RX_DV;
  logic                   RX_ERR;

  // Common
  logic                   CRS;
  logic                   COL;
endinterface
