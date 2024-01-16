FROM python:3-alpine

RUN apk update && \
    apk upgrade --available && \
    addgroup -g 1000 python && \
    adduser -u 1000 -D -G python python -h /app

USER python

WORKDIR /app

COPY app/requirements.txt /app
COPY app/gke_node_pool_scaler.py /app

RUN python -m pip install --upgrade pip && \
    python -m pip install -r /app/requirements.txt

ENTRYPOINT ["python", "/app/gke_node_pool_scaler.py"]
