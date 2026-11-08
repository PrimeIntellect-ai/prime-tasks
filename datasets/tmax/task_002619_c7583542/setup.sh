#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make tesseract-ocr wget curl
pip3 install pytest pillow

mkdir -p /app/src

# Create token.png
python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,50), 'SECRET_TOKEN_992', fill=(0,0,0))
img.save('/app/token.png')
"

# Create db.wal
for i in $(seq 1 50); do echo "SET key$i=value$i" >> /app/db.wal; done
echo "CORRUPT_ENTRY_xyz" >> /app/db.wal
for i in $(seq 51 100); do echo "SET key$i=value$i" >> /app/db.wal; done

# Download httplib.h
wget https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /app/src/httplib.h

# Create server.cpp
cat << 'EOF' > /app/src/server.cpp
#include "httplib.h"
#include <mutex>
#include <iostream>
#include <fstream>
#include <string>
#include <thread>
#include <chrono>

std::mutex m1;
std::mutex m2;

void load_wal() {
    std::ifstream file("/app/db.wal");
    std::string line;
    while (std::getline(file, line)) {
        if (line.find("CORRUPT") != std::string::npos) {
            std::cerr << "Corrupt entry found!" << std::endl;
            exit(1);
        }
    }
}

int main() {
    load_wal();
    httplib::Server svr;

    svr.Get("/query", [](const httplib::Request& req, httplib::Response& res) {
        auto auth = req.get_header_value("Authorization");
        if (auth != "Bearer SECRET_TOKEN_992") {
            res.status = 401;
            return;
        }
        std::lock_guard<std::mutex> lock1(m1);
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        std::lock_guard<std::mutex> lock2(m2);
        res.set_content("Query OK", "text/plain");
    });

    svr.Post("/update", [](const httplib::Request& req, httplib::Response& res) {
        auto auth = req.get_header_value("Authorization");
        if (auth != "Bearer SECRET_TOKEN_992") {
            res.status = 401;
            return;
        }
        std::lock_guard<std::mutex> lock2(m2);
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        std::lock_guard<std::mutex> lock1(m1);
        res.set_content("Update OK", "text/plain");
    });

    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
