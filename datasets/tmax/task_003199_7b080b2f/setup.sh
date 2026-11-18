#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential tesseract-ocr
    pip3 install pytest pytesseract Pillow

    # Create dummy library
    mkdir -p /opt/qa_libs
    echo 'void dummy() {}' > /tmp/dummy.c
    gcc -shared -fPIC -o /opt/qa_libs/libqa_utils.so /tmp/dummy.c

    # Create legacy harness
    mkdir -p /home/user/legacy_harness/src
    cat << 'EOF' > /home/user/legacy_harness/src/rules.cpp
#include <string>
#include <regex>
#include <fstream>
#include <sstream>

bool analyze_payload(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file.is_open()) return false;
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();

    if (content.find("<script>") != std::string::npos) return false;
    if (content.find("DROP TABLE") != std::string::npos) return false;
    if (content.find("UNION SELECT") != std::string::npos) return false;

    std::regex repeat_regex("(.)\\1{10,}");
    if (std::regex_search(content, repeat_regex)) return false;

    return true;
}
EOF

    cat << 'EOF' > /home/user/legacy_harness/src/main.cpp
#include <iostream>
#include <string>

bool analyze_payload(const std::string& filepath);

int main(int argc, char** argv) {
    if (argc > 1) {
        std::cout << analyze_payload(argv[1]) << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_harness/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(Tester)

add_executable(tester src/main.cpp src/rules.cpp)
target_link_libraries(tester qa_utils)
EOF

    # Create corpora
    mkdir -p /app/corpora/evil /app/corpora/clean
    echo "hello <script>alert(1)</script>" > /app/corpora/evil/1.txt
    echo "DROP TABLE users;" > /app/corpora/evil/2.txt
    echo "UNION SELECT * FROM passwords" > /app/corpora/evil/3.txt
    echo "aaaaaaaaaaaaaa" > /app/corpora/evil/4.txt

    echo "hello world" > /app/corpora/clean/1.txt
    echo "just a normal payload" > /app/corpora/clean/2.txt

    # Create whiteboard image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "LISTEN_PORT=8080 UPSTREAM_PORT=9000 HEADER: X-QA-Auth=Tango42", fill=(0,0,0))
img.save('/app/whiteboard.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /opt/qa_libs
