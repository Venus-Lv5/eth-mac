# Design Decisions - Ethernet MAC 10/100

> Document ghi chú những thay đổi quan trọng so với ethmac gốc
> Cập nhật: 2026-05-12

---

## 1. Tổng quan Design

Design này là phiên bản **đơn giản hóa** của [ethmac](https://opencores.org/projects/ethmac) tuân thủ chuẩn **IEEE 802.3**.

### Điểm khác biệt chính

| Khía cạnh | ethmac gốc | Design này |
|-----------|-----------|------------|
| Bus giao diện | WISHBONE | AHB-Lite |
| Số thanh ghi | 21 registers | 9 registers |
| MII Management | Có (đầy đủ) | Không (PHY cấu hình trước) |
| Cấu hình PAD/CRC | Per-register | Per-packet (trong BD) |
| Frame Length | Có PACKETLEN register | Cố định 64-1518 bytes |

---

## 2. Hệ thống thanh ghi

### 2.1 Danh sách thanh ghi

```
Địa chỉ  Tên thanh ghi     Mô tả
─────────────────────────────────────────────
0x00     MAC_CTRL         Điều khiển MAC (6 bits)
0x04     INT_STATUS       Trạng thái ngắt (R/W1C)
0x08     INT_EN           Bật/tắt ngắt
0x0C     MAC_ADDR_0       32 bits thấp địa chỉ MAC
0x10     MAC_ADDR_1       16 bits cao địa chỉ MAC
0x14     HASH_0           Hash multicast thấp
0x18     HASH_1           Hash multicast cao
0x20     FLOW_CTRL        Điều khiển flow control
0x24     TX_FLOW          Gửi PAUSE frame
```

### 2.2 MAC_CTRL Register

```
Bit   Tên       Mô tả
─────────────────────────────────────────────────
0     RX_EN     Bật bộ nhận
1     TX_EN     Bật bộ truyền
2     BRO       Nhận frame broadcast
3     FIL_EN    Lọc multicast bằng hash (IAM đổi tên)
4     PRO       Chế độ promiscuous
5     FULL      1 = Full duplex / 0 = Half Duplex (default = 1)

Default: 0x0020 (FULL=1)
```

### 2.3 INT_STATUS Register

```
Bit   Tên            Mô tả
─────────────────────────────────────────────────
0     TX_DONE        Truyền xong
1     TX_ERR         Lỗi truyền
2     RX_DONE        Nhận xong
3     RX_ERR         Lỗi nhận
4     RX_BUSY        Buffer không khả dụng
5     TX_CTRL_DONE   Gửi control frame xong
6     RX_CTRL_DONE   Nhận control frame xong

Kiểu: R/W1C (Write 1 to clear)
```

---

## 3. Các thanh ghi đã LOẠI BỎ

### 3.1 Thanh ghi hoàn toàn bị loại bỏ

| Thanh ghi | Địa chỉ gốc | Lý do |
|-----------|-------------|-------|
| IPGT | 0x0C | PHY tự xử lý |
| IPGR1 | 0x10 | PHY tự xử lý |
| IPGR2 | 0x14 | PHY tự xử lý |
| PACKETLEN | 0x18 | Cố định 64-1518 bytes |
| COLLCONF | 0x1C | Cố định MAXRET=15, COLLVALID=63 |
| TX_BD_NUM | 0x20 | Cố định 64 TX, 64 RX BD |
| MIIMODER | 0x28 | Không cần MII management |
| MIICOMMAND | 0x2C | Không cần MII management |
| MIIADDRESS | 0x30 | Không cần MII management |
| MIITX_DATA | 0x34 | Không cần MII management |
| MIIRX_DATA | 0x38 | Không cần MII management |
| MIISTATUS | 0x3C | Không cần MII management |

### 3.2 Bits trong MODER đã loại bỏ

| Bit | Tên | Lý do tuân thủ IEEE 802.3 |
|-----|-----|---------------------------|
| NOPRE | No Preamble | Preamble bắt buộc theo chuẩn |
| LOOPBCK | Loopback | Debug feature, không cần |
| IFG | IFG Override | Đường truyền tự xử lý |
| NOBCKOF | No Backoff | CSMA/CD bắt buộc binary exponential backoff |
| EXDFREN | Excess Defer | Defer limit cố định theo chuẩn |
| DLYCRCEN | Delayed CRC | CRC tính ngay sau SFD |
| HUGEN | Huge Packets | Frame > 1518 bytes không theo chuẩn |
| RECSMALL | Recv Small | Frame < 64 bytes không hợp lệ |

---

## 4. TX Buffer Descriptor (BD)

### 4.1 Cấu trúc TX BD (64-bit)

```
Word 0:
┌──────────────────────────────────────────────────────────────┐
│ 31                                              16 15      0 │
│                   LEN[15:0]                    │ Rsvd│Stt   │
└──────────────────────────────────────────────────────────────┘

Word 1:
┌──────────────────────────────────────────────────────────────┐
│ 31                                              16 15      0 │
│              TX Pointer[31:0] (địa chỉ buffer)              │
└──────────────────────────────────────────────────────────────┘

Stt[3:0]:
┌───┬───┬───┬───┐
│ IRQ │ WR │ PAD│ CRC │
└───┴───┴───┴───┘
```

### 4.2 Mô tả bit TX BD Status

| Bit | Tên | Mô tả |
|-----|-----|-------|
| 0 | CRC | 1: Thêm CRC vào frame |
| 1 | PAD | 1: Thêm padding vào frame ngắn |
| 2 | WR | 1: Wrap về BD đầu tiên |
| 3 | IRQ | 1: Tạo interrupt khi truyền xong |

### 4.3 Status bits ghi về (sau truyền)

| Bit | Tên | Mô tả |
|-----|-----|-------|
| 8 | UR | Underrun (FIFO rỗng) |
| 12:9 | RTRY | Số lần retry |
| 13 | RL | Retry limit reached |
| 14 | LC | Late collision |
| 15 | DF | Defer indication |
| 16 | CS | Carrier sense lost |

---

## 5. RX Buffer Descriptor (BD)

### 5.1 Cấu trúc RX BD (64-bit)

```
Word 0:
┌──────────────────────────────────────────────────────────────┐
│ 31                                              16 15      0 │
│                   LEN[15:0]                     │ Rsvd│Stt   │
└──────────────────────────────────────────────────────────────┘

Word 1:
┌──────────────────────────────────────────────────────────────┐
│ 31                                              16 15      0 │
│              RX Pointer[31:0] (địa chỉ buffer)              │
└──────────────────────────────────────────────────────────────┘

Stt[3:0]:
┌───┬───┬───┬───┐
│ E  │ IRQ│ WR │ - │
└───┴───┴───┴───┘
```

### 5.2 Mô tả bit RX BD Status

| Bit | Tên | Mô tả |
|-----|-----|-------|
| 0 | WR | 1: Wrap về BD đầu tiên |
| 1 | IRQ | 1: Tạo interrupt khi nhận xong |
| 2 | E | 1: Buffer trống, sẵn sàng nhận |

---

## 6. Cấu hình cố định

### 6.1 Frame Length
```
MINFL = 64 bytes
MAXFL = 1518 bytes
```

### 6.2 Buffer Descriptors
```
TX_BD_NUM = 64 (cố định)
RX_BD_NUM = 64 (cố định)
```

### 6.3 Collision
```
MAXRET = 15 (theo chuẩn Ethernet)
COLLVALID = 63 (collision window = 64 bytes)
```

---

## 7. Sơ đồ khối

```
┌─────────────────────────────────────────────────────────────────┐
│                        eth_ahb_top                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐     ┌────────────────┐     ┌─────────────┐ │
│   │ eth_ahb_    │────►│  eth_register  │────►│   Interrupt  │ │
│   │   slave     │     │   (9 regs)     │     │  Controller  │ │
│   └─────────────┘     └────────────────┘     └─────────────┘ │
│          │                    │                    ▲          │
│          │                    │                    │          │
│          ▼                    │                    │          │
│   ┌─────────────┐            │                    │          │
│   │ eth_bd_ram  │◄───────────┘                    │          │
│   │ (128 BDs)   │                                 │          │
│   └─────────────┘                                 │          │
│          │                                        │          │
│          ▼                                        │          │
│   ┌─────────────┐     ┌────────────────┐          │          │
│   │   TX DMA    │────►│   TX FIFO      │──────────┘          │
│   │             │     │                │                     │
│   │ • AHB Master│     └────────────────┘                     │
│   │ • BD Ctrl   │            │                              │
│   │ • PAD/CRC   │            ▼                              │
│   │   (per-pkt)│     ┌────────────────┐     ┌─────────────┐ │
│   └─────────────┘     │   eth_tx_mac   │────►│    MII      │ │
│          │           │                │     │   (TX)       │ │
│          │           └────────────────┘     └─────────────┘ │
│          │                                        ▲          │
│          ▼                                        │          │
│   ┌─────────────┐     ┌────────────────┐          │          │
│   │   RX DMA    │◄────│   eth_rx_mac   │          │          │
│   │             │     │                │          │          │
│   │ • AHB Master│     └────────────────┘     ┌─────┴──────┐   │
│   │ • BD Ctrl   │            │              │   MII      │   │
│   └─────────────┘     ┌────────────────┐    │   (RX)     │   │
│          │           │   eth_rx_addr   │◄───┘            │   │
│          │           │     check       │                  │   │
│          │           └────────────────┘                  │   │
│          ▼                                               │   │
│   ┌─────────────┐     ┌────────────────┐                │   │
│   │   RX FIFO   │────►│eth_mac_control │────────────────┘   │
│   │             │     │  (Flow Ctrl)   │                      │
│   └─────────────┘     └────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Checklist cho task tương lai

### Khi thay đổi Register
- [ ] Kiểm tra MAC_CTRL: chỉ 6 bits (không có PAD/CRC)
- [ ] PAD/CRC được cấu hình trong TX BD, không phải register
- [ ] FIL_EN = IAM (đổi tên, chức năng giữ)

### Khi thay đổi BD RAM
- [ ] TX BD bits 0-3: CRC, PAD, WR, IRQ (per-packet)
- [ ] RX BD bits 0-2: E, IRQ, WR
- [ ] Cấu hình cố định: 64 TX BD, 64 RX BD

### Khi thay đổi DMA
- [ ] TX DMA nhận PAD/CRC từ BD, không phải register
- [ ] Frame length cố định: 64-1518 bytes
- [ ] Collision retry cố định: max 15 lần

### KHÔNG cần thực hiện
- [ ] MII Management Module (đã loại bỏ hoàn toàn)
- [ ] IPG Timing (PHY tự xử lý)
- [ ] Configurable TX_BD_NUM (cố định 64)
- [ ] Configurable PACKETLEN (cố định 64-1518)

---

## 9. Liên kết tham khảo

- Specification gốc: `ethmac-master/doc/eth_speci.pdf`
- Specification mới: `Code/Specification.md`
- IEEE 802.3: https://standards.ieee.org/standard/802.3-2018.html
