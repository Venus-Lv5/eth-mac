ĐẶC TẢ KỸ THUẬT
THIẾT KẾ IP ETHERNET MAC 10/100 Mbps

1. Giới thiệu
1.1. Mô tả
IP Ethernet MAC 10/100 Mbps là một module phần cứng nằm ở tầng liên kết dữ liệu
(Data Link Layer) trong mô hình mạng OSI, cụ thể là phân lớp MAC. IP có nhiệm vụ
là cầu nối trung gian giữa lớp xử lý mức cao như TCP/IP và phần cứng vật lý PHY. IP
thực hiện xử lý các dữ liệu theo khung truyền Ethernet với chuẩn IEEE 802.3x bao
gồm cả việc đóng gói, kiểm tra trong cả quá trình truyền nhận dữ liệu.
1.2 Chức năng
- Giao tiếp với hệ thống
o Giao tiếp cấu hình với AHB master thông qua bus AHB-lite
o Hỗ trợ điều phối dữ liệu thông qua DMA
o Giao tiếp với PHY thông qua bus MII
- Chức năng chính của MAC core
o Hỗ trợ chế độ half duplex và full duplex
o Hỗ trợ cơ chế CDMA/CD với thuật toán backup nhị phân
o Tự động sinh và kiểm tra CRC (FCS)
o Tự động thêm padding cho frame không đủ kích thướt tối thiểu
o Hỗ trợ cấu hình thông qua hệ thống thanh ghi
- Lọc khung dữ liệu
o Nhận diện frame broadcast
o Lọc multicast dựa trên bảng băm (hash)
o Hỗ trợ chế dộ promiscous để nhận mọi frame
- Hỗ trợ tín hiệu ngắt
o Thông báo truyền/ nhận thành công frame
o Thông báo quá trình truyền/ nhận phát sinh lỗi
o Thông báo hệ thống đang bận
o Thông báo hệ thống đang truyền/ nhận 1 control frame (PAUSE FRAME)
- Hỗ trợ điều khiển luồng thông qua PAUSE FRAME theo chuẩn IEEE 802.3x

1.3  Sơ đồ khối

1.4  Các tín hiệu I/O
1.4.1  Tín hiệu giao diện AHB
| Tên tín hiệu  | Độ rộng  | Loại IO  |                                      | Mô tả  |
| ------------- | -------- | -------- | ------------------------------------ | ------ |
| hclk          | 1        | Input    | Clock hệ thống                       |        |
| Hresetn       | 1        | Input    | Reset hệ thống tích cực mức thấp     |        |
| Haddr         | [9:0]    | Input    | Địa chỉ truy cập                     |        |
| Hbusrt        | [2:0]    | Input    | Kiểu burst (single, incr, wrap,...)  |        |
| Hmastlock     | 1        | Input    | Khóa bus cho transaction atomic      |        |
| Hprot         | [3:0]    | Input    | Thuộc tính truy cập                  |        |
| Hsize         | [2:0]    | Input    | Kích thướt dữ liệu truy cập          |        |
| Hsel          | 1        | Input    | Tín hiệu chọn slave                  |        |
| Htrans        | [1:0]    | Input    | Loại transaction                     |        |
| Hwdata        | [31:0]   | Input    | Dữ liệu ghi từ master vào slave      |        |
| Hwrite        | 1        | Input    | Loại truy cập (đọc/ ghi)             |        |
| Hrdata        | [31:0]   | Output   | Dữ liệu đọc từ slave về master       |        |

| Hreadyout  | 1   | Output  | Tín hiệu slave báo sẵn sàng     |     |
| ---------- | --- | ------- | ------------------------------- | --- |
| Hresp      | 1   | Output  | Phản hồi từ slave (OKAY/ERROR)  |     |

1.4.2  Tín hiệu giao diện MII
| Tên tín hiệu  | Độ rộng  | Loại IO  |                                | Mô tả  |
| ------------- | -------- | -------- | ------------------------------ | ------ |
| tx_clk        | 1        | Input    | Clock PHY cấp cho việc truyền  |        |
| Tx_en         | 1        | Output   | Cho phép truyền frame          |        |
| Tx_er         | 1        | Output   | Báo lỗi đường truyền           |        |
| Txd           | [3:0]    | Output   | Dữ liệu truyền đế PHY          |        |
| Rx_clk        | 1        | Input    | Clock PHY cấp cho việc nhận    |        |
| Rx_dv         | 1        | Input    | Thông báo có dữ liệu hợp lệ    |        |
| Rx_er         | 1        | Input    | Báo lỗi trong quá trình nhận   |        |
| Rxd           | [3:0]    | Input    | Dữ liêu nhận từ PHY            |        |
PHY báo có tín hiệu trên đường
| CRS  | 1   | Input  |     |     |
| ---- | --- | ------ | --- | --- |
truyền
| COL  | 1   | Input  | Báo xảy ra va chạm (half-duplex)  |     |
| ---- | --- | ------ | --------------------------------- | --- |

1.4.3  Tín hiệu ngắt (Interrupt)
| Tên tín hiệu  | Độ rộng  | Loại IO  |                             | Mô tả  |
| ------------- | -------- | -------- | --------------------------- | ------ |
| INT           | 1        | Output   | Tín hiệu ngắt của hệ thống  |        |

2.  Hệ thống thanh ghi
2.1. Các đặc tính thanh ghi
| Đặc tính  |     |     | Mô tả  |     |
| --------- | --- | --- | ------ | --- |
RW  Có thể đọc và ghi (Read-Write)
RO  Chỉ có thể đọc (Read Only)

| WO  Chỉ có thể ghi (Write Only)  |     |     |     |
| -------------------------------- | --- | --- | --- |
R/W1C  Có thể đọc, ghi 1 để đặt thanh ghi về trạng thái ban đầu (Read/
Write 1 to clear)
| Rsvd  Dự trữ (reserved)  |     |     |     |
| ------------------------ | --- | --- | --- |

2.2.  Hệ thống thanh ghi
Địa chỉ truy cập từ 0x000 đến 0x3FF
| Địa chỉ offset  | Tên thanh ghi  |                             | Mô tả  |
| --------------- | -------------- | --------------------------- | ------ |
| 0x00            | MAC_CTRL       | Cấu hình chức năng của MAC  |        |
| 0x04            | INT_STATUS     | Trạng thái ngắt hiện tại    |        |
| 0x08            | INT_EN         | Cấu hình tín hiệu ngắt      |        |
Cấu hình 32 bit thấp của địa chỉ MAC
| 0x0C  | MAC_ADDR_0  |     |     |
| ----- | ----------- | --- | --- |
nguồn
Cấu hình 16 bit cao của địa chỉ MAC
| 0x10  | MAC_ADDR_1  |     |     |
| ----- | ----------- | --- | --- |
nguồn
| 0x14         | HASH_0     | Hash multicast thấp       |     |
| ------------ | ---------- | ------------------------- | --- |
| 0x18         | HASH_1     | Hash multicast cao        |     |
| 0x20         | FLOW_CTRL  | Cấu hình flow control     |     |
| 0x24         | TX_FLOW    | Cấu hình gửi PAUSE frame  |     |
| 0x28 – 0xFF  | Rsvd       | Dự trữ                    |     |

2.2.1.   Thanh ghi MAC_CTRL
|               | Loại           | Giá trị                               |        |
| ------------- | -------------- | ------------------------------------- | ------ |
| Bit  Tên bit  |                |                                       | Mô tả  |
|               | bit  mặc định  |                                       |        |
| 0  RX_EN      | RW             | 0  Kích hoạt khối nhận                |        |
| 1  TX_EN      | RW             | 0  Kích hoạt khối truyền              |        |
| 2  BRO        | RW             | 0  Kích hoạt nhận frame broadcast     |        |
| 3  FIL_EN     | RW             | 0  Kích hoạt lọc multicast bằng hash  |        |

Kích hoạt chế độ nhận toàn bộ
| 4   | PRO  | RW  | 0   |     |     |
| --- | ---- | --- | --- | --- | --- |
frame
Chọn chế độ Full Duplex/ Half
| 5   | FULL  | RW  | 1   |     |     |
| --- | ----- | --- | --- | --- | --- |
duplex
| [31:6]  | Rsvd  | RO  | 0   | Dự trữ  |     |
| ------- | ----- | --- | --- | ------- | --- |

2.2.2.   Thanh ghi INT_STATUS

Giá trị
Loại
| Bit  | Tên bit  |     |     | mặc  | Mô tả  |
| ---- | -------- | --- | --- | ---- | ------ |
bit
định
| 0   | TX_DONE  |     | R/W1C  | 0  Cờ báo truyền xong  |     |
| --- | -------- | --- | ------ | ---------------------- | --- |
| 1   | TX_ERR   |     | R/W1C  | 0  Cờ báo truyền lỗi   |     |
| 2   | RX_DONE  |     | R/W1C  | 0  Cờ báo nhận xong    |     |
| 3   | RX_ERR   |     | R/W1C  | 0  Cờ báo nhận lỗi     |     |
Cờ báo không có RX buffer
| 4   | RX_BUSY  |     | R/W1C  | 0   |     |
| --- | -------- | --- | ------ | --- | --- |
dùng được
Cờ báo gửi xong control
| 5   | TX_CTRL_DONE  |     | R/W1C  | 0   |     |
| --- | ------------- | --- | ------ | --- | --- |
frame
Cờ báo nhận xong control
| 6   | RX_CTRL_DONE  |     | R/W1C  | 0   |     |
| --- | ------------- | --- | ------ | --- | --- |
frame
| [31:7]  | Rsvd  |     | RO  | 0  Dự trữ  |     |
| ------- | ----- | --- | --- | ---------- | --- |

2.2.3.   Thanh ghi INT_EN

Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
Kích hoạt cờ báo truyền
| 0   | TX_DONE_EN  | RW  | 0   |     |
| --- | ----------- | --- | --- | --- |
xong
| 1   | TX_ERR_EN   | RW  | 0  Kích hoạt cờ báo truyền lỗi  |     |
| --- | ----------- | --- | ------------------------------- | --- |
| 2   | RX_DONE_EN  | RW  | 0  Kích hoạt cờ báo nhận xong   |     |
| 3   | RX_ERR_EN   | RW  | 0  Kích hoạt cờ báo nhận lỗi    |     |
Kích hoạt cờ báo không có
| 4   | RX_BUSY_EN  | RW  | 0   |     |
| --- | ----------- | --- | --- | --- |
RX buffer dùng được
Kích hoạt cờ báo gửi xong
| 5   | TX_CTRL_EN  | RW  | 0   |     |
| --- | ----------- | --- | --- | --- |
control frame
Kích hoạt cờ báo nhận xong
| 6   | RX_CTRL_EN  | RW  | 0   |     |
| --- | ----------- | --- | --- | --- |
control frame
| [31:7]  | Rsvd  | RO  | 0  Dự trữ  |     |
| ------- | ----- | --- | ---------- | --- |

2.2.4.   Thanh ghi MAC_ADDR_0
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
Cấu hình 32 bit thấp của địa
| [31:0]  | ADDR_LOW  | RW  | 32’h0  |     |
| ------- | --------- | --- | ------ | --- |
chỉ MAC nguồn

2.2.5.  Thanh ghi MAC_ADDR_1
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định

Cấu hình 16 bit cao của địa
| [15:0]  | ADDR_HIGH  | RW  | 32’h0  |     |
| ------- | ---------- | --- | ------ | --- |
chỉ MAC nguồn
| [31:16]  | Rsvd  | RW  | 0  Dữ trữ  |     |
| -------- | ----- | --- | ---------- | --- |

2.2.6.  Thanh ghi HASH_0
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
Cấu hình 32 bit thấp của
| [31:0]  | HASH_LOW  | RW  | 32’h0  |     |
| ------- | --------- | --- | ------ | --- |
bảng hash multicast

2.2.7.  Thanh ghi HASH_1
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
Cấu hình 32 bit cao của bảng
| [31:0]  | HASH_HIGH  | RW  | 32’h0  |     |
| ------- | ---------- | --- | ------ | --- |
hash multicast

2.2.8.  Thanh ghi FLOW_CTRL
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
| 0   | TX_FLOW_EN  | RW  | 0  Kích hoạt gửi PAUSE frame  |     |
| --- | ----------- | --- | ----------------------------- | --- |
Kích hoạt nhận PAUSE
| 1   | RX_FLOW_EN  | RW  | 0   |     |
| --- | ----------- | --- | --- | --- |
frame
Forward control frame lên
| 2   | PASS_CTRL  | RW  | 0   |     |
| --- | ---------- | --- | --- | --- |
host

| [31:3]  | Rsvd  | RO  | 32’h0  Dự trữ  |     |
| ------- | ----- | --- | -------------- | --- |

2.2.9.  Thanh ghi TX_FLOW
Giá trị
Loại
| Bit  | Tên bit  |     | mặc  | Mô tả  |
| ---- | -------- | --- | ---- | ------ |
bit
định
Ghi 1 để yêu cầu phát
| 0   | SEND_PAUSE  | RW/SC  | 0   |     |
| --- | ----------- | ------ | --- | --- |
PAUSE frame
| [16:1]   | PAUSE_TIME  | RW  | 0  Giá trị pause time  |     |
| -------- | ----------- | --- | ---------------------- | --- |
| [31:17]  | Rsvd        | RO  | 32’h0  Dự trữ          |     |

3.  Vận hành

IP gồm nhiều khối quản lý việc vận hành của hệ thống, trong đó có:
-  AHB Slave đóng vai trò trung gian kết nối giữa IP và hệ thống bên ngoài thông
qua bus AHB-lite

- Register chứa những thanh ghi cấu hình và trạng thái của IP
- TX/ RX Decriptor Buffer lưu trữ các mô tả vùng nhớ cho các dữ liệu truyền nhận
- TX/ RX DMA Engine hỗ trợ điều phối dữ liệu truyền/ nhận giữa IP và RAM hệ
thống
- TX/ RX FIFO là bộ đệm trung gian giữa DMA Engine và lõi Eth trong giao tiếp
dữ liệu
- TX/ RX Eth MAC thực hiện các chức năng truyền/ nhận dữ liệu với PHY thông
qua bus MII
- MAC Controller điều phối và kiểm soát hoạt động của bộ truyền/ nhận dữ liệu
- Interrupt Controller tạo tín hiệu ngắt cho hệ thống
3.1. Reset
- Khi tín hiệu Hreset_n tích cực mức thấp, đặt lại toàn bộ thanh ghi và RAM về giá
trị mặc định
3.2. Cách vận hành của giao diện AHB
- Khối AHB Slave tiếp nhận các transaction đọc/ ghi từ AHB Master và truy xuất
đến khối Register và khối Decriptor Buffer RAM, trong đó:
o Vùng địa chỉ từ 0x000 đến 0x3FF dùng cho việc đọc ghi hệ thống thanh ghi
cho việc cấu hình và đọc trạng thái hệ thống
o Vùng địa chỉ từ 0x400 đến 0x7FF dùng cho việc cấu hình những mô tả bộ
nhớ cho việc điều phối dữ liệu truyền nhận của hệ thống
3.3. Decriptor Buffer
Decriptor Buffer điều phối quá trình lấy dữ liệu để truyền hoặc lưu dữ liệu khi
nhận vào RAM hệ thống. DB lưu trữ những cấu hình cần thực hiện cho frame và
chỉ dẫn địa chỉ trong RAM hệ thống cho việc lấy và ghi dữ liệu.

Decriptor Buffer RAM lưu tổng cộng 128 DB từ địa chỉ 0x400 đến 0x7FF dược
chia thành 2 thành phần gồm 64 TX DB từ địa chỉ 0x400 – 0x5FF sử dụng cho
việc truyền và 64 RX DB từ địa chỉ 0x600 – 0x7FF sử dụng cho việc nhận. Mỗi
DB có độ rộng 64 bit trong đó 32 bit đầu chứa độ dài, trạng thái và cấu hình xử lý
dữ liệu, 32 bit sau chứa con trỏ đến buffer liên kết trong RAM hệ thống.
3.3.1. TX Decriptor Buffer
TX Decriptor Buffer chứa các mô tả truyền tải chứa thông tin về các bộ đệm liên
kết (độ dài, trạng thái) và con trỏ đến các bộ đệm chứa dữ liệu liên quan.
ADDR = Offset + 0 (Word 0)
31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16
LEN
15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
Rsvd UR RTRY[3:0] RL LC DF CS RD IRQ WR PAD CRC
ADDR = Offset + 4 (Word 1)
31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16
TXPNT
15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
TXPNT
Giá trị
Tên Loại
Bit mặc Mô tả
bit bit
định
CRC Enable
0 CRC RW 0 0: IP không cần thêm CRC vào cuối frame
1: IP cần thêm CRC vào cuối frame

PAD Enable
| 1  PAD  | RW  | 0  0: IP không cần thêm pad vào frame  |
| ------- | --- | -------------------------------------- |
1: IP cần thêm pad vào frame
Wrap
0: Thông báo BD này chưa phải là BD
cuối
| 2  WR  | RW  | 0   |
| ------ | --- | --- |
1: BD này là BD cuối; sau khi BD này
được dùng xong, IP quay về Tx BD đầu
tiên
Interrupt Enable
0: Không tạo ngắt
| 3  IRQ  | RW  | 0   |
| ------- | --- | --- |
1: Sau khi truyền xong dữ liệu sẽ thông
báo ngắt TX_DONE hoặc TX_ERR
RX DB Ready
0: Thông báo DB chưa sẵn sàng, không
| 4  RD  | RW  | 0  được phép chỉnh sửa thông tin  |
| ------ | --- | --------------------------------- |
1: Thông báo DB đã sẵn sàng, nhận sửa
chữa thông tin từ master
Carrier Sense Lost
| 5  CS  | RW  | 0  IP đặt bit này bằng 1 khi mất tín hiệu  |
| ------ | --- | ------------------------------------------ |
Carrier Sense trong lúc đang truyền frame
Defer Indication
| 6  DF  | RW  | 0  . Frame bị trì hoãn trước khi truyền thành  |
| ------ | --- | ---------------------------------------------- |
công do đường truyền bận.
Late Collision
| 7  LC  | RW  | 0  IP đặt bit này khi xung đột xảy ra sau cửa  |
| ------ | --- | ---------------------------------------------- |
sổ collision; việc truyền bị dừng lại
| 8  RL  | RW  | 0  Retransmission Limit  |
| ------ | --- | ------------------------ |

IP đặt bit này khi vượt quá số lần retry tối
đa do xung đột liên tiếp trên đường truyền
Retry Count
[12:9]  RTRY  RW  4’h0  Số lần retry trước khi frame được truyền
thành công
Underrun
| 13  |     | UR  | RW  | 4’h0  | IP đặt bit này khi TX FIFO rỗng trong lúc  |     |     |     |     |
| --- | --- | --- | --- | ----- | ------------------------------------------ | --- | --- | --- | --- |
đang truyền buffer này
| [15:14]  |     | Rsvd  | RO  | 2’h0  | Dự trữ  |     |     |     |     |
| -------- | --- | ----- | --- | ----- | ------- | --- | --- | --- | --- |
[31:16]  LEN  RW  16’h0  Số byte của buffer liên kết cần truyền

|      |          |     | Loại  | Giá trị   |     |     |        |     |     |
| ---- | -------- | --- | ----- | --------- | --- | --- | ------ | --- | --- |
| Bit  | Tên bit  |     |       |           |     |     | Mô tả  |     |     |
|      |          |     | bit   | mặc định  |     |     |        |     |     |
Transmit Pointer
[31:0]  TXPNT  RW  32’h0  Con trỏ đến buffer trong System RAM
chứa dữ liệu cần truyền

3.3.2.  RX Decriptor Buffer
RX Decriptor Bufer chứa thông tin về các khung đã nhận (độ dài, trạng thái) và
con trỏ đến các bộ đệm chứa dữ liệu liên quan.
ADDR = Offset + 0
31  30  29  28  27  26  25  24  23  22  21  20  19  18  17  16
LEN
| 15  | 14  13  | 12  | 11  10  | 9  8   | 7   | 6   | 5  4     | 3  2   | 1  0     |
| --- | ------- | --- | ------- | ------ | --- | --- | -------- | ------ | -------- |
|     | Rsvd    |     | CF      | M  OR  | IS  | TL  | SF  CRC  | LC  E  | IRQ  WR  |

ADDR = Offset + 4
31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16
RXPNT
15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
RXPNT
Giá trị
Tên Loại
Bit mặc Mô tả
bit bit
định
Wrap
0: Thông báo BD này chưa phải là BD
cuối
0 WR RW 0
1: BD này là BD cuối; sau khi BD này
được dùng xong, IP quay về Tx BD đầu
tiên
Interrupt Enable
0: Không tạo ngắt
1 IRQ RW 0
1: Sau khi truyền xong dữ liệu sẽ thông
báo ngắt TX_DONE hoặc TX_ERR
Empty
0: Thông báo buffer đã được lấp đầy dữ
liệu hoặc dừng do lỗi, ngừng hoạt động
2 E RW 0
cho đến khi đc bật
1: buffer trống, sẵn sàng nhận hoặc đang
nhận dữ liệu
Late Collision
3 LC RW 0 IP đặt bit này khi xung đột xảy ra sau cửa
sổ collision trong lúc nhận frame

Rx CRC Error
| 4  CRC  | RW  | 0  IP đặt bit này khi frame nhận chứa lỗi  |
| ------- | --- | ------------------------------------------ |
CRC
Short Frame
| 5  SF  | RW  | 0  IP đặt bit này khi frame nhận ngắn hơn độ  |
| ------ | --- | --------------------------------------------- |
dài tối thiểu
Too Long.
| 6  TL  | RW  | 0  IP đặt bit này khi frame nhận vượt độ dài  |
| ------ | --- | --------------------------------------------- |
tối đa cho phép
Invalid Symbol
| 7  IS  | RW  | 0  IP đặt bit này khi PHY phát hiện ký tự  |
| ------ | --- | ------------------------------------------ |
không hợp lệ trên đường truyền
Overrun
| 8  OR  | RW  | 0  IP đặt bit này khi RX FIFO đầy trong lúc  |
| ------ | --- | -------------------------------------------- |
đang nhận frame
Miss.
0 = frame được nhận do khớp địa chỉ.
1 = frame được nhận do chế độ
promiscuous. IP đặt M cho các frame
| 9  M  | RW  | 0  được chấp nhận ở chế độ promiscuous  |
| ----- | --- | --------------------------------------- |
nhưng không khớp địa chỉ của trạm —
trong chế độ promiscuous, M giúp
firmware xác định frame có thực sự gửi
đến trạm này không
Control Frame.
0 = frame dữ liệu thông thường được
| 10  CF  | RW  | 0   |
| ------- | --- | --- |
nhận. 1 = frame nhận được là PAUSE
control frame

| [15:11]  | Rsvd  RO  | 2’h0  Dự trữ  |
| -------- | --------- | ------------- |
[31:16]  LEN  RW  16’h0  Số byte nhận được liên kết với BD này

Loại  Giá trị
| Bit  | Tên bit  | Mô tả  |
| ---- | -------- | ------ |
bit  mặc định
Receive Pointer.
[31:0]  RXPNT  RW  32’h0  Con trỏ đến buffer trong System RAM để
IP ghi dữ liệu nhận vào