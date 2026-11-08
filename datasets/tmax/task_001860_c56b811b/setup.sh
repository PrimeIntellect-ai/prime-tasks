#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest redis minio boto3 flask

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/services
    mkdir -p /home/user/tests

    cat << 'EOF' > /home/user/services/docker-compose.yml
version: '3.8'
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
  minio:
    image: minio/minio
    command: server /data
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports:
      - "9000:9000"
  flask:
    image: python:3.9-slim
    command: python3 -m http.server 5000
    ports:
      - "5000:5000"
EOF

    cat << 'EOF' > /home/user/tests/run_tests.sh
#!/bin/bash
echo "Test harness placeholder"
EOF
    chmod +x /home/user/tests/run_tests.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
