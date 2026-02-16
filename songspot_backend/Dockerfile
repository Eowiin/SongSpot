FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app/songspot_backend
ARG TARGETARCH

# ffmpeg is needed by demucs for mp3 output
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY songspot_backend/requirements.txt /tmp/requirements.txt
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        # torchcodec has no usable wheel for linux/arm64 in this stack.
        grep -Ev '^torchcodec==' /tmp/requirements.txt > /tmp/requirements.docker.txt; \
    else \
        cp /tmp/requirements.txt /tmp/requirements.docker.txt; \
    fi \
    && pip install --upgrade pip \
    && pip install -r /tmp/requirements.docker.txt

COPY songspot_backend /app/songspot_backend

EXPOSE 8000

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
