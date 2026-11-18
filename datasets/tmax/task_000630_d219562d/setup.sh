#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        cmake \
        make \
        g++ \
        git
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /home/user/log_pipeline/src
    mkdir -p /home/user/logs

    # Generate video
    ffmpeg -f lavfi -i "color=c=blue:s=320x240:d=42" -f lavfi -i "color=c=red:s=320x240:d=18" -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0" -c:v libx264 /app/dashboard_cam.mp4

    # Generate logs
    python3 -c '
import random
from datetime import datetime, timedelta

start = datetime(2023, 10, 1, 0, 0, 0)
for svc in ["a", "b", "c"]:
    with open(f"/home/user/logs/service_{svc}.log", "w") as f:
        for i in range(300):
            ts = start + timedelta(seconds=i)
            f.write(f"{ts.isoformat()} [{svc.upper()}] Log entry {i}\n")
'

    # Create CMakeLists.txt
    cat << 'EOF' > /home/user/log_pipeline/CMakeLists.txt
cmake_minimum_required(VERSION 3.14)
project(log_pipeline)

set(CMAKE_CXX_STANDARD 17)

# Deliberate conflict
find_package(fmt 8.0 REQUIRED)

include(FetchContent)
FetchContent_Declare(
  spdlog
  GIT_REPOSITORY https://github.com/gabime/spdlog.git
  GIT_TAG v1.11.0
)
FetchContent_MakeAvailable(spdlog)

add_executable(sanitizer src/parser.cpp)
target_link_libraries(sanitizer PRIVATE spdlog::spdlog fmt::fmt)
EOF

    # Create parser.cpp
    cat << 'EOF' > /home/user/log_pipeline/src/parser.cpp
#include <iostream>
#include <string>

bool parse_payload(const std::string& payload, size_t& index) {
    if (index >= payload.length()) return true;
    if (payload.substr(index, 9) == "[RECURSE]") {
        // Bug: doesn't advance index
        return parse_payload(payload, index);
    }
    if (payload[index] == '[') {
        index++;
        while (index < payload.length() && payload[index] != ']') {
            if (!parse_payload(payload, index)) return false;
        }
        if (index < payload.length() && payload[index] == ']') {
            index++;
            return true;
        }
        return false; // unclosed
    }
    index++;
    return true;
}

int main() {
    std::string input;
    if (std::getline(std::cin, input)) {
        size_t idx = 0;
        if (parse_payload(input, idx) && idx == input.length()) {
            return 0;
        } else {
            return 1;
        }
    }
    return 0;
}
EOF

    # Create corpora
    echo "[a [b [c]]]" > /app/corpora/clean/1.txt
    echo "[hello]" > /app/corpora/clean/2.txt
    echo "valid_log" > /app/corpora/clean/3.txt

    echo "[RECURSE]" > /app/corpora/evil/1.txt
    echo "[a [RECURSE]]" > /app/corpora/evil/2.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user /app
