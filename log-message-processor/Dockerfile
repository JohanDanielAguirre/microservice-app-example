# Log Message Processor (Python)
FROM python:3.10
WORKDIR /app

# Install build tools in case wheels are not available
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_CHANNEL=log_channel

CMD ["python", "main.py"]

