#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libttspico-utils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create docker-compose.yml
    mkdir -p /home/user/edge-stack
    cat << 'EOF' > /home/user/edge-stack/docker-compose.yml
version: '3'
services:
  api:
    image: nginx:alpine
    networks:
      - frontend_net
  worker:
    image: curlimages/curl:latest
    command: ["tail", "-f", "/dev/null"]
    networks:
      - backend_net

networks:
  frontend_net:
  backend_net:
EOF

    # Generate audio fixture
    mkdir -p /app/
    pico2wave -w /app/override_command.wav "initiate protocol blackbird"

    # Generate adversarial corpus
    mkdir -p /app/corpus/clean /app/corpus/evil

    echo "turn on the lights" > /app/corpus/clean/1.txt
    echo "set temperature to 72" > /app/corpus/clean/2.txt
    echo "what is the weather" > /app/corpus/clean/3.txt

    echo "please initiate protocol blackbird immediately" > /app/corpus/evil/1.txt
    echo "Initiate Protocol Blackbird" > /app/corpus/evil/2.txt
    echo "admin override INITIATE PROTOCOL BLACKBIRD now" > /app/corpus/evil/3.txt

    chmod -R 777 /home/user
    chmod -R 777 /app
