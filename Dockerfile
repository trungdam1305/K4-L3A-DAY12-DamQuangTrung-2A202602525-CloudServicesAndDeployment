# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
#   - Multi-stage: stage `builder` cài dependency vào virtualenv, stage
#     runtime chỉ copy virtualenv + source → image nhỏ, không mang compiler.
#   - Base image slim.
#   - COPY requirements.txt + pip install TRƯỚC khi COPY source → tận dụng
#     layer cache: sửa code không phải cài lại thư viện.
#   - Chạy bằng user thường (UID 10001), không phải root.
#   - HEALTHCHECK gọi /health.
#   - Đọc cổng từ biến PORT (cloud tự gán), mặc định 8000.
#
# Kiểm tra:  pytest tests/test_cp2.py -v
# Build thử: docker build -t day12-agent:prod .
# ═══════════════════════════════════════════════════════════════════

# ─── Stage 1: builder ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
COPY requirements.txt .
RUN pip install -r requirements.txt

# ─── Stage 2: runtime ──────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /app

# Code thuộc root, user `app` chỉ đọc được: nếu app bị chiếm quyền, kẻ tấn
# công cũng không sửa được code đang chạy.
COPY --from=builder /opt/venv /opt/venv
COPY app ./app
COPY utils ./utils

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\", \"8000\")}/health', timeout=3)" || exit 1

# Dạng shell để nội suy ${PORT} và ${LOG_LEVEL}; `exec` để uvicorn là PID 1 và
# nhận SIGTERM trực tiếp. uvicorn chỉ nhận log level viết thường.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --log-level \"$(echo ${LOG_LEVEL:-INFO} | tr '[:upper:]' '[:lower:]')\""]
