FROM python:3.12-slim
LABEL description="SwiftEats food delivery analytics"
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home analytics
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=analytics:analytics . .
RUN mkdir -p logs data/generated reports
USER analytics
CMD ["python", "scripts/run_analytics.py"]
