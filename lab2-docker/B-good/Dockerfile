# ==========================================
# СТАДИЯ 1: Сборщик
# ==========================================

FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

# Cначала копируем ТОЛЬКО requirements
COPY backend/requirements.txt .

# Ставим зависимости без кеша, чтобы не раздувать образ
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================================
# СТАДИЯ 2: Финальный легкий образ 
# ==========================================
FROM python:3.12-slim-bookworm

WORKDIR /app

# Забираем установленные пакеты из стадии 1
COPY --from=builder /install /usr/local

# Копируем исходный код приложения
COPY backend/ /app/backend/
COPY frontend/ /app/frontend/

# Создаем непривилегированного пользователя
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

# Healthcheck без установки curl (используем встроенный python)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "5000"]