#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl ffmpeg nginx
    pip3 install pytest

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/src
    mkdir -p /app

    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:9005; # Typo, should be 9000
        }
    }
}
EOF

    cat << 'EOF' > /home/user/src/backend.cpp
#include "httplib.h"
#include <iostream>
#include <cstdlib>

int main() {
    httplib::Server svr;

    svr.Get("/process", [](const httplib::Request &, httplib::Response &res) {
        // Missing FFmpeg extraction logic
        // Missing red frame counting logic
        // Missing backup creation logic
        res.set_content("{\"red_frames\": 0}", "application/json");
    });

    // Binding to wrong port intentionally
    std::cout << "Starting server on port 8000..." << std::endl;
    svr.listen("127.0.0.1", 8000); 
    // Missing raw TCP socket on 9001
    return 0;
}
EOF

    wget -qO /home/user/src/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h

    # Create dummy video file
    ffmpeg -f lavfi -i color=c=blue:s=320x240:d=2 -f lavfi -i color=c=red:s=320x240:d=1 -f lavfi -i color=c=blue:s=320x240:d=2 -f lavfi -i color=c=red:s=320x240:d=1 -f lavfi -i color=c=blue:s=320x240:d=2 -f lavfi -i color=c=red:s=320x240:d=1 -f lavfi -i color=c=blue:s=320x240:d=1 -filter_complex "[0:v][1:v][2:v][3:v][4:v][5:v][6:v]concat=n=7:v=1[outv]" -map "[outv]" -c:v libx264 -y /app/surveillance.mp4 || true

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
