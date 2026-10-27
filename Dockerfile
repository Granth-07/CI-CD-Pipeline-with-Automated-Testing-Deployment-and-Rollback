FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    CHROMA_MODE=persistent \
    CHROMA_PATH=/data

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN mkdir -p /data && useradd -m -u 1000 appuser && chown -R appuser:appuser /app /data

COPY --chown=appuser:appuser app/ ./app/

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=5s \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
