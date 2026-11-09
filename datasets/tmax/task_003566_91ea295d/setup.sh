#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        cmake \
        g++ \
        nlohmann-json3-dev

    pip3 install pytest Pillow

    mkdir -p /home/user/router_utility
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate routing_spec.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'ROUTE | MAX_REQ_PER_MINUTE | ALLOWED_PARAMS', fill=(0,0,0))
d.text((10,30), '/api/v1/users | 20 | id, format', fill=(0,0,0))
d.text((10,50), '/api/v1/billing | 5 | invoice_id', fill=(0,0,0))
d.text((10,70), '/api/v2/data | 50 | query, limit', fill=(0,0,0))
img.save('/app/routing_spec.png')
"

    # Create C++ skeleton
    cat << 'EOF' > /home/user/router_utility/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(router_utility)
set(CMAKE_CXX_STANDARD 17)
add_executable(request_validator main.cpp router.cpp url_parser.cpp)
EOF

    cat << 'EOF' > /home/user/router_utility/url_parser.cpp
#include <string>
#include <string_view>

std::string_view parse_url_param(const std::string& url) {
    std::string temp = url + "_parsed";
    return temp; // Bug: returns string_view of local variable
}
EOF

    cat << 'EOF' > /home/user/router_utility/router.cpp
#include <iostream>
#include <string_view>

std::string_view parse_url_param(const std::string& url);

void validate_request() {
    // To be implemented
}
EOF

    cat << 'EOF' > /home/user/router_utility/main.cpp
#include <iostream>

void validate_request();

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <directory>\n";
        return 1;
    }
    validate_request();
    return 0;
}
EOF

    # Create corpus files
    echo '{"route": "/api/v1/users", "params": {"id": "1", "format": "json"}, "timestamp": 1000}' > /app/corpus/clean/req1.json
    echo '{"route": "/api/v1/users", "params": {"id": "../1", "format": "json"}, "timestamp": 1000}' > /app/corpus/evil/req1.json

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
