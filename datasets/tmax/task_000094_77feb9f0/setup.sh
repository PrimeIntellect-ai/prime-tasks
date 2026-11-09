#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest

mkdir -p /app

# Generate video with exactly 14 red frames
ffmpeg -f lavfi -i "color=c=black:s=100x100:d=10" -vf "drawbox=x=0:y=0:w=100:h=100:color=red@1:t=fill:enable='between(n,10,23)'" -c:v libx264 -preset ultrafast -frames:v 300 /app/server_ops.mp4

# Create config_options.txt
cat << 'EOF' > /app/config_options.txt
America/New_York,en_US.UTF-8,1a2b3c4d5e
Asia/Tokyo,ja_JP.UTF-8,2b3c4d5e6f
Europe/London,en_GB.UTF-8,3c4d5e6f7g
Australia/Sydney,en_AU.UTF-8,4d5e6f7g8h
America/Los_Angeles,en_US.UTF-8,5e6f7g8h9i
Europe/Berlin,de_DE.UTF-8,6f7g8h9i0j
Asia/Shanghai,zh_CN.UTF-8,7g8h9i0j1k
America/Chicago,en_US.UTF-8,8h9i0j1k2l
Europe/Madrid,es_ES.UTF-8,9i0j1k2l3m
Asia/Dubai,ar_AE.UTF-8,0j1k2l3m4n
America/Toronto,en_CA.UTF-8,1k2l3m4n5o
Europe/Rome,it_IT.UTF-8,2l3m4n5o6p
Asia/Seoul,ko_KR.UTF-8,3m4n5o6p7q
Europe/Paris,fr_FR.UTF-8,9a8b7c6d5e4f3g2h
America/Mexico_City,es_MX.UTF-8,5o6p7q8r9s
Pacific/Auckland,en_NZ.UTF-8,6p7q8r9s0t
Europe/Amsterdam,nl_NL.UTF-8,7q8r9s0t1u
Asia/Singapore,en_SG.UTF-8,8r9s0t1u2v
America/Sao_Paulo,pt_BR.UTF-8,9s0t1u2v3w
Africa/Johannesburg,en_ZA.UTF-8,0t1u2v3w4x
EOF

# Create docker-compose.yml
cat << 'EOF' > /app/docker-compose.yml
version: '3'
services:
  proxy:
    image: nginx:alpine
    ports:
      - "8080:80"
    networks:
      - frontend_net
  time_service:
    image: python:3.10-slim
    command: python3 /app/time_service.py
    volumes:
      - ./time_service.py:/app/time_service.py
    networks:
      - backend_net
networks:
  frontend_net:
  backend_net:
EOF

# Create time_service.py
cat << 'EOF' > /app/time_service.py
import missing_library
print("Starting service...")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
