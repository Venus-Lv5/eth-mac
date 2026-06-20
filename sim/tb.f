+incdir+${ETH_IP_VERIF_PATH}/sequences
+incdir+${ETH_IP_VERIF_PATH}/testcases
+incdir+${ETH_IP_VERIF_PATH}/tb
+incdir+${ETH_IP_VERIF_PATH}/regmodel
+incdir+${ETH_IP_VERIF_PATH}/regmodel/register

// Compilation VIP design (agent) list
-f ${PHY_VIP_ROOT}/phy_vip.f
-f ${AHB_VIP_ROOT}/ahb_vip.f

// Compilation Environment
${ETH_IP_VERIF_PATH}/regmodel/register/eth_register_pkg.sv
${ETH_IP_VERIF_PATH}/regmodel/eth_regmodel_pkg.sv
${ETH_IP_VERIF_PATH}/tb/env_pkg.sv
${ETH_IP_VERIF_PATH}/sequences/seq_pkg.sv
${ETH_IP_VERIF_PATH}/testcases/test_pkg.sv
${ETH_IP_VERIF_PATH}/tb/testbench.sv

