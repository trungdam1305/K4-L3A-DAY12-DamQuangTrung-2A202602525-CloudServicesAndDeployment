# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder in nghiêng dưới mỗi câu bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Đàm Quang Trung  Mã học viên: 2A202602525

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: deploy lên Railway nhưng quên đặt `AGENT_API_KEY` trên dashboard.

- Nếu mặc định là `"changeme"`: app vẫn lên, `/health` 200, Railway báo deploy
  thành công. URL là public, ai đoán thử `X-API-Key: changeme` (khóa mặc định
  phổ biến nhất) là gọi được `/ask` và tiêu ngân sách LLM của tôi. Tôi chỉ phát
  hiện khi nhìn hóa đơn.
- Không có mặc định: app chết ngay lúc khởi động, deploy bị đánh dấu fail, bản
  cũ vẫn chạy, và log chỉ thẳng nguyên nhân. Tôi đã chạy thử container thiếu
  key và nhận được:

  ```
  pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
  agent_api_key
    Field required [type=missing, ...]
  ERROR:    Application startup failed. Exiting.
  ```

Khi thử câu này tôi còn phát hiện bài làm ban đầu **chưa thật sự fail fast**:
`get_settings()` chỉ được gọi lần đầu trong `/ask`, nên thiếu key thì app vẫn
lên, `/health` vẫn 200 và lỗi chỉ lộ ra thành HTTP 500 khi có người gọi `/ask`.
Tôi sửa bằng cách gọi `get_settings()` trong `lifespan` lúc khởi động (commit
"CP1 fix"). Bài học: khai báo trường bắt buộc chưa đủ, cấu hình còn phải được
đọc *lúc khởi động*.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Một dòng log thật lấy từ `docker compose logs agent` sau khi gọi `/ask`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T07:38:41.391653+00:00", "user_id": "sv01", "tokens_in": 402, "tokens_out": 43, "cost_usd": 8.61e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` không làm được:

1. **Lọc và tổng hợp theo trường.** Ví dụ tính tổng `cost_usd` theo `user_id`
   trong ngày để biết ai đang tốn tiền, hoặc đếm số `ask_completed` mỗi phút.
   Với chuỗi tự do thì phải viết regex đoán nội dung, và chuỗi đó không có
   user hay chi phí.
2. **Cảnh báo tự động.** Ví dụ báo động khi `level == "error"` hoặc khi một
   `user_id` vượt 0.5 USD/giờ. Máy đọc được `level` và `timestamp` chuẩn ISO
   nên sắp xếp và đối chiếu được giữa nhiều container.

Tôi thấy điều này ngay trên Railway: log `service_started` hiển thị thành
`[INFO] event="service_started" ... version="1.0.0"`. Railway đã tự tách JSON
thành các trường có thể lọc, còn dòng `print` thường chỉ là một khối chữ.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ... MB |
| Multi-stage | ... MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `FROM python:3.11`) | 1.73 GB |
| Multi-stage (`python:3.11-slim`) | 310 MB |

Đo bằng `docker images` sau khi build Dockerfile gốc (lấy từ commit đầu) với
tag `agent:single` và Dockerfile hiện tại với tag `agent:multi`.

Phần chênh lệch khoảng 1.42 GB gồm:

- **Base image** chiếm gần hết: `python:3.11` nặng 1.61 GB, còn
  `python:3.11-slim` chỉ 189 MB. Bản đầy đủ mang theo gcc, make, header `-dev`,
  git và nhiều thư viện hệ thống chỉ cần khi *biên dịch*, không cần khi *chạy*.
- **Cache của pip**: trong bản 1 stage có `/root/.cache` 17 MB. Bản
  multi-stage cài vào `/opt/venv` (92 MB) ở stage builder rồi chỉ copy venv
  sang, nên không mang cache và thư mục build theo.
- **File thừa** do `COPY . .`: Dockerfile, `grade.py`, `nginx/`,
  `render.yaml`... Bản multi-stage chỉ copy `app/` và `utils/` (124 KB).

Nhận xét: phần lớn mức giảm đến từ việc đổi sang base slim, còn multi-stage
giữ cho image runtime không có công cụ build và cache. Với Dockerfile gốc và
`.dockerignore` gốc (chỉ loại `.git`), `COPY . .` còn chép cả `.env` vào image,
tức secret nằm trong image.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Tôi đổi `SERVICE_VERSION` trong `app/main.py` rồi build lại với
`--progress=plain`.

**Dockerfile hiện tại:** mất **2 giây**.

- Dùng lại cache (`CACHED`): toàn bộ stage builder (`python -m venv`,
  `COPY requirements.txt`, `RUN pip install`), và ở stage runtime các bước
  `groupadd/useradd`, `WORKDIR`, `COPY --from=builder /opt/venv`.
- Chạy lại: `COPY app ./app` (vì file trong đó đổi) và `COPY utils ./utils`
  (mọi layer *sau* một layer bị đổi đều phải chạy lại, dù `utils` không đổi).

**Bản thử đặt `COPY . .` trước `RUN pip install`:** mất **100 giây**. Chỉ
`FROM` và `WORKDIR` còn cache. `COPY . .` bị đổi nên `RUN pip install` phải
tải và cài lại toàn bộ thư viện. Hơn nữa, sửa *bất kỳ* file nào, kể cả
README, cũng làm vỡ cache của bước pip.

Nguyên tắc: Docker cache theo từng layer, theo thứ tự. Thứ ít đổi
(`requirements.txt`, dependency) đặt trước, thứ đổi thường xuyên (code) đặt
sau cùng.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy bằng root:

1. Code có lỗ hổng, ví dụ một thư viện parse input bị lỗi dẫn tới chạy lệnh
   tùy ý (RCE), hoặc path traversal cho phép ghi file.
2. Kẻ tấn công chạy lệnh với quyền của process. Nếu process là **root
   (UID 0)** thì họ đọc được mọi file trong container, kể cả biến môi trường
   chứa `AGENT_API_KEY` và `REDIS_URL`, sửa được code, và cài thêm công cụ
   bằng `apt`.
3. Root trong container cũng là **UID 0 trên kernel của host** (container
   không có một kernel riêng). Nếu có thêm một điểm yếu, ví dụ mount
   `/var/run/docker.sock`, chạy `--privileged`, mount thư mục host, hoặc một
   lỗ hổng kernel/runc như CVE-2019-5736 (vốn cần root trong container để ghi
   đè binary `runc` của host), thì kẻ tấn công thoát ra ngoài và **là root
   trên host**, điều khiển được mọi container khác.

`USER app` (UID 10001) cắt chuỗi ở **bước 2 → 3**: code bị chiếm chỉ chạy
bằng một user thường. Họ không cài được gói hệ thống, không ghi được vào
thư mục hệ thống, và nếu có thoát ra thì cũng chỉ là UID 10001 không có
quyền gì trên host. Tôi đã kiểm tra: `docker compose exec agent id` trả về
`uid=10001(app) gid=10001(app)`.

Khi rà soát, tôi thấy `USER` thôi chưa đủ: bản đầu tôi copy code bằng
`COPY --chown=app:app`, nên user `app` vẫn **sửa được chính code đang chạy**
(thử `touch /app/app/main.py` thì thành công). Tôi bỏ `--chown` để code thuộc
root và user `app` chỉ đọc được. Chạy lại lệnh đó thì báo
`Permission denied`.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request trong khoảng 2 giây** (gấp đôi hạn mức).

Cách làm với bộ đếm theo phút đồng hồ:

- 10:00:59: gửi 10 request. Bộ đếm của phút 10:00 lên 10/10, vẫn hợp lệ.
- 10:01:00: bộ đếm reset về 0. Gửi tiếp 10 request, bộ đếm của phút 10:01
  lên 10/10, cũng hợp lệ.

Kết quả là 20 request trong khoảng 1–2 giây mà không bị chặn lần nào. Lặp lại
ở mỗi ranh giới phút thì hạn mức thực tế tại các thời điểm "nhạy cảm" là
2 lần con số trên giấy.

Với sliding window (sorted set, score là timestamp), mỗi request đều đếm lại
số request trong **60 giây ngay trước nó**. Request thứ 11 lúc 10:01:00 vẫn
thấy 10 request từ 10:00:59 nằm trong cửa sổ nên bị chặn 429. Bất kỳ khoảng
60 giây nào cũng không quá 10 request. Tôi quan sát được trên bản deploy:
15 request liên tiếp cho ra 10 lần `200` rồi 5 lần `429`.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

**Khác nhau:**

- Rate limit đếm **số request** trong 60 giây gần nhất (cửa sổ ngắn), bảo vệ
  tài nguyên và chống spam hay DoS. Mã lỗi `429`, và tự hết sau vài giây.
- Cost guard cộng dồn **số tiền** theo user theo tháng (key
  `cost:<user>:<YYYY-MM>`), bảo vệ ngân sách. Mã lỗi `402`, và chỉ hết khi
  sang tháng mới hoặc được nâng hạn mức.

**Rate limit cho qua nhưng cost guard chặn:** một user gửi đều 5 request mỗi
phút (dưới hạn mức 10), nhưng mỗi câu hỏi dài gần 2000 ký tự và lịch sử 20
message được gửi kèm, nên mỗi lượt tốn nhiều token. Chạy như vậy vài ngày thì
tổng chi phí vượt 10 USD và cost guard trả `402`, dù chưa lúc nào vi phạm
rate limit. Trong test tôi mô phỏng bằng cách đặt sẵn `cost:sv-test:<tháng>`
là 999, và request đầu tiên đã bị `402`.

**Cost guard cho qua nhưng rate limit chặn:** một script gửi `"hi"` liên tục.
Mỗi request chỉ tốn khoảng 0.00002 USD nên ngân sách gần như không suy
chuyển, nhưng request thứ 11 trong một phút bị `429`. Tôi thấy đúng điều này
khi gọi 15 lần liên tiếp vào bản deploy.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Giả sử 3 container sau load balancer, orchestrator restart container khi
health check fail 3 lần liên tiếp (chu kỳ 10 giây), và endpoint gộp có gọi
Redis.

1. **t=0s:** Redis mất kết nối. Cả 3 container **cùng lúc** trả 503 ở
   endpoint gộp, vì cả 3 dùng chung một Redis.
2. **t≈0–30s:** load balancer thấy cả 3 không healthy và rút cả 3 khỏi vòng
   xoay. Mọi request, kể cả những request không cần Redis, đều nhận 502/503.
3. **t≈30s:** sau 3 lần fail, orchestrator coi cả 3 process là "chết" và
   **restart cả 3 cùng lúc**. Restart không sửa được gì vì lỗi nằm ở Redis,
   không nằm ở process. Mọi request đang xử lý dở bị cắt ngang.
4. **t≈30s+:** Redis có lại, nhưng 3 container đang khởi động lại (cold
   start), nên còn thêm một khoảng downtime. Nếu Redis chập chờn, các
   container rơi vào vòng restart liên tục (crash loop, bị backoff), và
   thời gian gián đoạn kéo dài hơn nhiều so với 30 giây.

Tách hai endpoint: `/health` chỉ hỏi "process còn sống không" nên vẫn 200,
không container nào bị restart. `/ready` trả 503 để load balancer tạm ngừng
gửi traffic. Khi Redis trở lại, `/ready` lên 200 ngay và traffic chạy lại mà
không cần khởi động gì. Tôi đã thử trên máy: `docker compose stop redis` thì
`/health` vẫn `200`, `/ready` trả `503 {"status":"not ready","redis":false}`;
bật Redis lại thì `/ready` về `200` ngay.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

`--scale agent=3` với cấu hình compose hiện tại bị trùng cổng `8000:8000`,
nên tôi dùng một file override tạm: bỏ port của agent và thêm service
`nginx` (dùng `nginx/nginx.conf` có sẵn) làm load balancer ở cổng 8088. Sau
đó gọi `/ask` 6 lần với cùng một `X-User-Id`.

Quan sát thật (lấy container từ log `ask_completed`):

| Request | Container xử lý | `history_length` |
|---|---|---|
| 1 | agent-1 | 0 |
| 2 | agent-2 | 2 |
| 3 | agent-1 | 4 |
| 4 | agent-3 | 6 |
| 5 | agent-2 | 8 |
| 6 | agent-1 | 10 |

Request chạy qua cả 3 container, nhưng `history_length` vẫn tăng đều 2 sau
mỗi lượt, vì mọi container đọc và ghi cùng một list `history:<user>` trong
Redis.

Nếu lưu trong một dict Python, mỗi container chỉ nhớ các request *nó* xử lý.
Với đúng thứ tự trên, agent-1 thấy request 1, 3, 6 nên trả 0, 2, 4; agent-2
thấy request 2, 5 nên trả 0, 2; agent-3 thấy request 4 nên trả 0. Dãy số sẽ là
**0, 0, 2, 0, 2, 4**: nhảy lên xuống thất thường, agent lúc nhớ lúc quên. Hơn
nữa, mỗi lần container restart hoặc deploy bản mới thì dict mất sạch và
history về 0.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Lỗi tôi gặp khi kiểm tra bản deploy trên Railway: gọi `/ask` có API key
bằng curl trong Git Bash trên Windows:

```
curl -X POST $URL/ask -H "X-API-Key: ..." -d '{"question":"Deploy là gì?"}'
HTTP/1.1 400 Bad Request
{"detail":"There was an error parsing the body"}
```

**Tìm nguyên nhân:**

- `/health`, `/ready` đều 200 và `/ask` không key trả đúng 401, nên service
  và auth không có vấn đề.
- 400 không phải 401/422, và thông điệp là *parse body*, nghĩa là FastAPI
  không đọc được JSON, tức lỗi xảy ra trước khi vào code của tôi.
- Vòng test rate limit ngay sau đó dùng câu hỏi ASCII `"test"` thì trả 200.
  Khác biệt duy nhất là chữ có dấu, nên nghi vấn chuyển sang encoding: đối
  số dòng lệnh trên Windows không được gửi đi dưới dạng UTF-8, nên body
  thành JSON có byte không hợp lệ.

**Sửa:** ghi body ra file UTF-8 rồi gửi bằng
`--data-binary @q.json -H "Content-Type: application/json; charset=utf-8"`.
Kết quả 200 và câu trả lời hiển thị đúng tiếng Việt. Không cần sửa code,
nhưng tôi ghi chú lại trong `DEPLOYMENT.md`.

Một lỗi khác tôi tránh được *trước* khi deploy: `railway.toml` ban đầu có
`startCommand = "uvicorn ... --port $PORT"`. Với builder Dockerfile, Railway
chạy start command không qua shell nên `$PORT` sẽ không được thay giá trị.
Tôi bỏ `startCommand` để dùng `CMD ["sh", "-c", "... --port ${PORT:-8000}"]`
của Dockerfile. Log deploy xác nhận uvicorn chạy ở cổng `8080` do Railway
cấp.
