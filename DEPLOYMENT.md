# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Đàm Quang Trung |
| Mã học viên | 2A202602525 |
| Repo | https://github.com/trungdam1305/K4-L3A-DAY12-DamQuangTrung-2A202602525-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://k4-l3a-day12-damquangtrung-2a202602525-cloudserv-production.up.railway.app |
| Platform | Railway (builder Dockerfile, cấu hình trong `railway.toml`). Deploy do GitHub Actions thực hiện (`.github/workflows/ci.yml`): chỉ chạy khi test và build xanh trên `main` |
| Ngày deploy | 2026-09-28 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Railway tự gán (log: uvicorn chạy ở cổng 8080), không set tay |
| `AGENT_API_KEY` | ✅ | đặt trong dashboard, không nằm trong repo |
| `REDIS_URL` | ✅ | Redis service trong cùng project Railway, tham chiếu `${{Redis.REDIS_URL}}` (private network `redis.railway.internal`) |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Dán output của các lệnh trên vào đây:

Chạy ngày 2026-09-28 với `URL=https://k4-l3a-day12-damquangtrung-2a202602525-cloudserv-production.up.railway.app` (đã bỏ bớt header `date`/`server`/`x-railway-*`; API key được đọc từ biến môi trường, không ghi ra):

```
$ curl -i $URL/health
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 57
x-hikari-trace: sin1.hs0s
Connection: keep-alive

{"status":"ok","service":"day12-agent","version":"1.0.0"}


$ curl -i $URL/ready
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 31
x-hikari-trace: sin1.98a6
Connection: keep-alive

{"status":"ready","redis":true}


$ curl -i -X POST $URL/ask (không có API key)
HTTP/1.1 401 Unauthorized
Content-Type: application/json
www-authenticate: ApiKey
Content-Length: 39
x-hikari-trace: sin1.hs0s
Connection: keep-alive

{"detail":"invalid or missing API key"}


$ curl -i -X POST $URL/ask (có X-API-Key, body UTF-8)
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 279
x-hikari-trace: sin1.hs0s
vary: accept-encoding
Connection: keep-alive

{"answer":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.","user_id":"sv-test","history_length":0,"cost_usd":2.145e-05,"tokens":{"in":3,"out":35}}


$ rate limit: 15 lần /ask
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

Ghi chú: gửi câu hỏi có dấu tiếng Việt bằng `-d '...'` trong Git Bash trên Windows
có thể bị 400 do đối số dòng lệnh không phải UTF-8; gửi body từ file UTF-8
(`--data-binary @q.json`) thì trả 200 như trên.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt hoặc curl

---

## Nếu Dùng Phương Án Dự Phòng

Không áp dụng — service đã deploy thành công lên Railway (`LOCAL_FALLBACK=false`).
