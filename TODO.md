# TODO LIST - Các khối cần bổ sung

> Cập nhật: 2026-05-12
> Xếp hạng theo: Tầm quan trọng + Độ phức tạp

---

## 🔴 ƯU TIÊN CAO - Không thể thiếu

### 1. [P1] TX MAC Core (`eth_tx_mac.v`)
**Mức độ:** 🔴 Rất cao
**Độ phức tạp:** ⭐⭐⭐ Trung bình-cao

**Chức năng cần thiết:**
- FSM điều khiển truyền frame (Idle → Preamble → SFD → Data → PAD → CRC → Jam)
- Sinh preamble (0x55 x 7) và SFD (0xD5)
- Padding tự động cho frame < 64 bytes
- Tính và append CRC32
- CSMA/CD: collision detection, jam, backoff (binary exponential)
- Half/Full duplex handling
- Carrier sense, deferral

**Signals cần có:**
```
Input:
  - tx_clk (từ PHY)
  - tx_start (từ TX DMA)
  - tx_end (từ TX DMA)
  - tx_data[7:0] (từ TX FIFO)
  - tx_crc_en, tx_pad_en (từ TX BD)
  - tx_underrun (từ TX DMA)
  - full_duplex (từ register)
  - carrier_sense, collision (từ PHY)

Output:
  - tx_data[3:0] (MII data)
  - tx_en (MII enable)
  - tx_er (MII error)
  - tx_done, tx_retry, tx_abort (status về DMA)
  - tx_used_data (báo DMA đã dùng data)
  - retry_cnt[3:0], retry_lmt, late_coll (status)
```

**Tham khảo:** `ethmac-master/rtl/verilog/eth_txethmac.v`

---

### 2. [P2] RX MAC Core (`eth_rx_mac.v`)
**Mức độ:** 🔴 Rất cao
**Độ phức tạp:** ⭐⭐⭐ Trung bình-cao

**Chức năng cần thiết:**
- FSM nhận frame (Idle → Preamble → SFD → Data)
- Kiểm tra preamble và SFD
- Byte count cho độ dài frame
- CRC verification
- Phát hiện lỗi: CRC, short frame, long frame, symbol error
- Truncate frame nếu quá buffer

**Signals cần có:**
```
Input:
  - rx_clk (từ PHY)
  - rx_data[3:0] (từ PHY)
  - rx_dv, rx_er (từ PHY)
  - max_fl (từ constant, 1518)

Output:
  - rx_data[7:0] (đến RX DMA)
  - rx_valid (data hợp lệ)
  - rx_start (start of frame)
  - rx_end (end of frame)
  - rx_abort (lỗi/address mismatch)
  - rx_byte_cnt[1:0] (số byte hợp lệ trong nibble cuối)
  - byte_cnt[15:0] (tổng bytes đã nhận)
```

**Tham khảo:** `ethmac-master/rtl/verilog/eth_rxethmac.v`

---

### 3. [P3] RX Address Check (`eth_rx_addr_check.v`)
**Mức độ:** 🔴 Rất cao
**Độ phức tạp:** ⭐⭐ Trung bình

**Chức năng cần thiết:**
- So sánh địa chỉ MAC nhận được với MAC của station
- Kiểm tra broadcast (FF:FF:FF:FF:FF:FF)
- Kiểm tra multicast dựa trên hash table
- Promiscuous mode (nhận tất cả)
- Đánh dấu AddressMiss trong RX BD

**Signals cần có:**
```
Input:
  - rx_clk
  - rx_data[7:0]
  - rx_valid
  - rx_start
  - rx_end
  - mac_addr[47:0]
  - hash_0[31:0], hash_1[31:0]
  - pro_en, bro_en, fil_en (từ register)

Output:
  - rx_pass (frame được chấp nhận)
  - address_miss (nhận do promiscuous)
  - control_frame (là PAUSE frame)
```

**Tham khảo:** `ethmac-master/rtl/verilog/eth_rxaddrcheck.v`

---

## 🟡 ƯU TIÊN TRUNG BÌNH - Cần thiết cho đầy đủ

### 4. [P4] MAC Control / Flow Control (`eth_mac_control.v`)
**Mức độ:** 🟡 Trung bình
**Độ phức tạp:** ⭐⭐ Trung bình

**Chức năng cần thiết:**
- Xử lý PAUSE frame (IEEE 802.3x)
- Gửi PAUSE frame khi nhận yêu cầu từ register
- Nhận diện và xử lý PAUSE frame từ remote
- Multiplex giữa data frame và control frame
- Điều khiển padding/CRC cho control frame

**Signals cần có:**
```
Input:
  - tx_clk, rx_clk
  - tx_flow_en, rx_flow_en, pass_ctrl (từ register)
  - send_pause, pause_time (từ TX_FLOW register)
  - tx_data, tx_start, tx_end, tx_used_data (từ TX DMA)
  - rx_data, rx_valid (từ RX MAC)

Output:
  - tx_data, tx_start, tx_end (đến TX MAC)
  - tx_crc_en, tx_pad_en (cấu hình cho control frame)
  - received_pause_frm
  - set_pause_timer
  - tx_pause_done (về register)
```

**Tham khảo:** `ethmac-master/rtl/verilog/eth_maccontrol.v`

---

### 5. [P5] CRC Generator (`eth_crc.v`)
**Mức độ:** 🟡 Trung bình
**Độ phức tạp:** ⭐⭐ Thấp-Trung bình

**Chức năng cần thiết:**
- Tính CRC32 (Ethernet polynomial: 0x04C11DB7)
- 4-bit parallel CRC cho MII interface
- Support delayed CRC mode (optional)

**Tham khảo:** `ethmac-master/rtl/verilog/eth_crc.v`

---

## 🟢 ƯU TIÊN THẤP - Có thể tối ưu sau

### 6. [P6] TX State Machine + Counters (`eth_tx_statems.v`)
**Mức độ:** 🟢 Thấp (có thể tích hợp vào eth_tx_mac)
**Độ phức tạp:** ⭐⭐ Trung bình

**Chức năng (nếu tách riêng):**
- TX state machine FSM
- Byte/word counter
- Collision window tracking
- Retry counter

---

### 7. [P7] RX State Machine + Counters (`eth_rx_statems.v`)
**Mức độ:** 🟢 Thấp (có thể tích hợp vào eth_rx_mac)
**Độ phức tạp:** ⭐⭐ Trung bình

**Chức năng (nếu tách riêng):**
- RX state machine FSM
- Byte counter
- Frame length validation

---

## 📋 BẢNG TỔNG HỢP

| # | Khối | Ưu tiên | Phức tạp | Lines ước tính | Phụ thuộc |
|---|------|----------|-----------|----------------|------------|
| 1 | eth_tx_mac | 🔴 P1 | ⭐⭐⭐ | ~800-1000 | CRC, registers |
| 2 | eth_rx_mac | 🔴 P2 | ⭐⭐⭐ | ~600-800 | CRC, addr_check |
| 3 | eth_rx_addr_check | 🔴 P3 | ⭐⭐ | ~400-500 | hash comparison |
| 4 | eth_mac_control | 🟡 P4 | ⭐⭐ | ~300-400 | TX/RX MAC |
| 5 | eth_crc | 🟡 P5 | ⭐⭐ | ~150-200 | TX/RX MAC |
| 6 | eth_tx_statems | 🟢 P6 | ⭐⭐ | ~300-400 | (có thể bỏ) |
| 7 | eth_rx_statems | 🟢 P7 | ⭐⭐ | ~300-400 | (có thể bỏ) |

---

## 🎯 KẾ HOẠCH ĐỀ XUẤT

### Phase 1: Core TX/RX (2-3 tuần)
```
1. eth_crc.v          → Cần cho cả TX và RX
2. eth_tx_mac.v       → Khối truyền chính
3. eth_rx_mac.v       → Khối nhận chính
4. eth_rx_addr_check  → Lọc địa chỉ
```

### Phase 2: Flow Control (1 tuần)
```
5. eth_mac_control.v  → PAUSE frame handling
```

### Phase 3: Integration & Test (1-2 tuần)
```
- Kết nối các khối vào eth_ahb_top
- Testbench cơ bản
- Integration test
```

---

## 📁 Cấu trúc thư mục đề xuất

```
Code/rtl/
├── eth_ahb_top.v        ✅ Có
├── eth_ahb_slave.v      ✅ Có
├── eth_ahb_master.v     ✅ Có
├── eth_register.v       ✅ Có
├── eth_bd_ram.v         ✅ Có
├── eth_tx_dma.v         ✅ Có
├── eth_rx_dma.v         ✅ Có
├── eth_fifo.v           ✅ Có
├── eth_interrupt.v      ✅ Có
├── eth_sram_256x32.v    ✅ Có
│
├── eth_tx_mac.v         ❌ CẦN TẠO (P1)
├── eth_rx_mac.v         ❌ CẦN TẠO (P2)
├── eth_rx_addr_check.v  ❌ CẦN TẠO (P3)
├── eth_mac_control.v    ❌ CẦN TẠO (P4)
├── eth_crc.v            ❌ CẦN TẠO (P5)
└── eth_defines.v        ❌ CẦN TẠO (constants)
```

---

## 🔗 Signoff Checklist

### Trước khi đánh dấu hoàn thành P1:
- [ ] eth_tx_mac.v compile không lỗi
- [ ] FSM xử lý đúng collision
- [ ] Padding tự động cho frame < 64 bytes
- [ ] CRC được tính và append đúng
- [ ] Half/Full duplex hoạt động đúng

### Trước khi đánh dấu hoàn thành P2:
- [ ] eth_rx_mac.v compile không lỗi
- [ ] Preamble/SFD detection đúng
- [ ] CRC verification hoạt động
- [ ] Short/Long frame detection đúng

### Trước khi đánh dấu hoàn thành P3:
- [ ] eth_rx_addr_check.v compile không lỗi
- [ ] MAC address matching đúng
- [ ] Broadcast nhận đúng khi BRO=1
- [ ] Multicast hash filtering hoạt động
- [ ] Promiscuous mode hoạt động
