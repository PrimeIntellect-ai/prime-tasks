#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        ffmpeg \
        cron \
        tzdata \
        locales \
        python3-scipy \
        python3-numpy \
        curl

    pip3 install --no-cache-dir pytest fastapi uvicorn python-multipart

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tmp
    mkdir -p /app

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /home/user/error.log;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/access.log;
    client_body_temp_path /home/user/client_body;
    fastcgi_temp_path /home/user/fastcgi_temp;
    proxy_temp_path /home/user/proxy_temp;
    scgi_temp_path /home/user/scgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;

    server {
        listen 8080;
        location /upload {
            proxy_pass http://unix:/home/user/tmp/wrong.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backend.py
from fastapi import FastAPI, UploadFile, File
import os

app = FastAPI()

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    tz = os.environ.get("TZ", "Unknown")
    lc = os.environ.get("LC_ALL", "Unknown")
    return {"filename": file.filename, "tz": tz, "lc": lc}
EOF

    cat << 'EOF' > /home/user/start_backend.sh
#!/bin/bash
python3 -m uvicorn backend:app --uds /home/user/api.sock &
EOF
    chmod +x /home/user/start_backend.sh

    # Generate dummy audio file
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=2" -ar 44100 -ac 2 /app/voicemail.wav

    # Ensure locales are available
    locale-gen fr_FR.UTF-8
    update-locale

    # Nginx needs to be started by the test environment or user, 
    # but we will just ensure it exists and config is ready.
    # The test checks if nginx is running, so we'll start it in a wrapper if needed, 
    # or rely on the agent environment to start it.
    # Actually, we can start it in the background for the test if the test runs in the same shell,
    # but container builds don't persist processes. We will just leave it ready.

    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
