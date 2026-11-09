#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ cmake make nginx socat
pip3 install pytest

mkdir -p /home/user/qa_env/backend/src
mkdir -p /home/user/qa_env/backend/lib
mkdir -p /home/user/qa_env/backend/include
mkdir -p /home/user/qa_env/nginx_temp

# 1. Create the shared library (libencode)
cat << 'EOF' > /home/user/qa_env/backend/src/encode.cpp
#include "encode.h"
#include <string>
#include <vector>

static const std::string base64_chars = 
             "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
             "abcdefghijklmnopqrstuvwxyz"
             "0123456789+/";

std::string base64_encode(const std::string &in) {
    std::string out;
    int val = 0, valb = -6;
    for (unsigned char c : in) {
        val = (val << 8) + c;
        valb += 8;
        while (valb >= 0) {
            out.push_back(base64_chars[(val >> valb) & 0x3F]);
            valb -= 6;
        }
    }
    if (valb > -6) out.push_back(base64_chars[((val << 8) >> (valb + 8)) & 0x3F]);
    while (out.size() % 4) out.push_back('=');
    return out;
}
EOF

cat << 'EOF' > /home/user/qa_env/backend/include/encode.h
#ifndef ENCODE_H
#define ENCODE_H
#include <string>
std::string base64_encode(const std::string &in);
#endif
EOF

g++ -I/home/user/qa_env/backend/include -fPIC -shared -o /home/user/qa_env/backend/lib/libencode.so /home/user/qa_env/backend/src/encode.cpp

# 2. Create the main C++ service
cat << 'EOF' > /home/user/qa_env/backend/src/main.cpp
#include <iostream>
#include <string>
#include <sstream>
#include "encode.h"

int main() {
    std::string input;
    std::getline(std::cin, input);

    // Rudimentary JSON parsing to extract sum
    double sum = 0.0;
    size_t start = input.find('[');
    size_t end = input.find(']');
    if (start != std::string::npos && end != std::string::npos) {
        std::string array_content = input.substr(start + 1, end - start - 1);
        std::stringstream ss(array_content);
        std::string token;
        while (std::getline(ss, token, ',')) {
            sum += std::stod(token);
        }
    }

    std::string json_out = "{\"sum\": " + std::to_string(sum) + "}";
    std::cout << "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n";
    std::cout << base64_encode(json_out) << std::flush;
    return 0;
}
EOF

# 3. Create flawed CMakeLists.txt
cat << 'EOF' > /home/user/qa_env/backend/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(NumService)

include_directories(include)

add_executable(num_service src/main.cpp)

# BUG: The linker doesn't know where libencode.so is, and RPATH is missing
target_link_libraries(num_service encode)
EOF

# 4. Create flawed Nginx config
cat << 'EOF' > /home/user/qa_env/nginx.conf
worker_processes 1;
error_log /home/user/qa_env/nginx_temp/error.log;
pid /home/user/qa_env/nginx_temp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/qa_env/nginx_temp/client_body;
    fastcgi_temp_path /home/user/qa_env/nginx_temp/fastcgi_temp;
    proxy_temp_path /home/user/qa_env/nginx_temp/proxy_temp;
    scgi_temp_path /home/user/qa_env/nginx_temp/scgi_temp;
    uwsgi_temp_path /home/user/qa_env/nginx_temp/uwsgi_temp;

    access_log /home/user/qa_env/nginx_temp/access.log;

    server {
        listen 8080;
        server_name localhost;

        # TODO: Configure /api to reverse proxy to http://127.0.0.1:9000
        # location /api {
        # ...
        # }
    }
}
EOF

# 5. Create build & serve script
cat << 'EOF' > /home/user/qa_env/build_and_serve.sh
#!/bin/bash
cd /home/user/qa_env/backend
mkdir -p build && cd build
cmake ..
make

echo "Starting socat server on port 9000..."
socat TCP-LISTEN:9000,reuseaddr,fork EXEC:./num_service &
EOF
chmod +x /home/user/qa_env/build_and_serve.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
