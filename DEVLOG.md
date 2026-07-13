# DEVLOG — Tcl_Safety-Factor- (Safety Factor tool)

> 🔄 **HANDOFF (2026-07-10):** Đây là repo em của
> [Tcl_VonMises-stress-on-mutiple-step-load-](https://github.com/NeuJin/Tcl_VonMises-stress-on-mutiple-step-load-)
> — **đọc DEVLOG.md của repo đó trước** (kiến trúc chung, toàn bộ gotchas
> API HyperView, lịch sử commit chi tiết). File này chỉ ghi phần **khác
> biệt/riêng của Safety Factor**.
>
> **Nhánh làm việc: `feat/multi-window-annotate`** (main chỉ có 1 commit gốc
> `5440f5c`, chưa merge).
>
> **File chính: `safetyfactor_lib.tcl`** (namespace `::SafetyFactor`) — được
> `HVTools_Panel.tcl` (ở repo VonMises) source làm tab "Safety Factor" của
> panel gộp. **Khi deploy phải copy file này vào cùng thư mục
> `HVTools_Panel.tcl`** — nếu thiếu, panel vẫn mở nhưng tab SF hiện dòng
> nhắc đỏ và vô hiệu.
>
> **Khác Max Stress ở chỗ nào:** SF không sweep nhiều frame — chỉ 1 load
> case cố định (`SUBCASE`, mặc định 1) tìm **MIN** Safety Factor (thay vì
> MAX stress), nên không có derived case, không có cột Angle. Note style
> trắng của SF cũng khác: KHÔNG có dòng "SF: Loadcase..." (đã bỏ theo yêu
> cầu user), thứ tự là Node ID → MIN → dòng spacer đánh dấu 2 đầu bằng ".".

---

## API công khai (`::SafetyFactor::`)

```
RunExport selectionSets (outputDir)   — quét min SF mọi window → SafetyFactor_Summary.csv
RunAnnotate setID (outputDir)         — vẽ marker+note từ CSV lên mọi window
QueryNodeValue winIdx nodeID          — re-query 1 giá trị (không cần Angle)
ApplyDisplay legendOn meshMode        — giống Max Stress, dùng chung recipe
ListSets / ResolveSet input table     — resolve input là ID SỐ hoặc TÊN set (vd gõ "Pos3")
```

## File output

- `SafetyFactor_Summary.csv` — `WindowID,SetName,MinNodeID,MinSafetyFactor,LoadCaseLabel`
- (chưa có report pivot riêng cho SF — user nói "không cần trên SF", chỉ Max Stress có `Make Report`)

## Bug riêng đã giải (ngoài các gotcha chung ở DEVLOG repo VonMises)

- **Data type SF có padding y hệt bệnh chung** — label thật `"1.  Endure_SF_A"`
  (2 space). `SetupContour` normalize-match với `rctrl GetDataTypeList`
  trước khi Set (biến `RESOLVED_DT`), KHÔNG dùng `DATATYPE` thô trực tiếp
  ở bất kỳ đâu khác (kể cả query).
- **`GetSelectionSetHandle` id không tồn tại → set rỗng không lỗi** — đây
  là nguyên nhân gốc khiến toàn bộ set "no data returned" ban đầu (chẩn
  đoán qua `SF_Debug.tcl`, không phải lỗi data type như nghi ngờ đầu tiên).
- Contour cần full apply recipe giống Max Stress (animator refresh +
  display options + Draw) — `SetupContour` đã bọc sẵn.

## `SF_Debug.tcl` — script chẩn đoán độc lập

9 lớp debug tuần tự (model/subcase/data-type-list/contour-apply/
query-setup/selection-set/query node.id đơn/query node.id+contour.value/
sweep biến thể Result-Type). Dùng khi query trả 0 rows mà không rõ tầng
nào lỗi — chạy trên window ĐANG ACTIVE (giống điều kiện script gốc chạy
được), không phải qua panel. Đã dùng để tìm ra 2 root cause liên tiếp
(selection-set rỗng, rồi data-type padding) trong 1 buổi debug.

## Lịch sử commit (nhánh `feat/multi-window-annotate`, mới nhất trước)

- `dcfc2e8` fix: chữ note đen (style trắng, HV2022 mặc định trắng)
- `47a7617` fix: gọi `::post::LoadSettings` sau source legend GUI-saved
- `95894d0` feat: ô Legend TCL optional (mirror Max Stress)
- `908faa2` feat: `ApplyDisplay` — toggle legend + display mode
- `588f66a` tweak: bỏ dòng load-case trong note, Node ID lên đầu, dòng spacer 2 dấu chấm
- `1ef7b9b`, `a80129c`, `38b8492` feat/tweak: style note trắng (giống Max Stress, xem DEVLOG kia)
- `5fa8df3` feat: precision + component variable
- `f7dd7c0` feat: toggle "Show note header"
- `547df9b` feat: bảng Results sửa được + re-query (Node ID only, không Angle)
- `8468e8d` fix: **ROOT CAUSE 2** — data type padding, normalize-match `GetDataTypeList`
- `d9e59bb` fix: full contour-apply recipe; debug tool dùng set thật không rỗng
- `8d7093d` fix: **ROOT CAUSE 1** — resolve selection set qua `GetSelectionSetList`
- `7841283` debug: thêm `SF_Debug.tcl`
- `0835ec3`, `446f2d5` fix: các lần thử đầu (activate window, model ID thật, verify data type) — đường dẫn dò tìm trước khi ra root cause thật
- `e720673` feat: bản multi-window đầu tiên (export + annotate + panel + lib refactor từ script gốc `Conrod_SF_Find_NodeSet.tcl`)

## Việc còn treo

- Không có report pivot riêng cho SF (chủ đích, user không yêu cầu).
- Cùng các mục treo chung với Max Stress (xem DEVLOG repo VonMises):
  animator-sync fix áp dụng tương tự cho SF chưa được test riêng lần cuối
  (SF vốn chỉ 1 frame cố định nên ít bị ảnh hưởng bởi bug animator, nhưng
  `SetupContour` vẫn nên được xem lại nếu SF cũng gặp hiện tượng hình sai
  frame).
