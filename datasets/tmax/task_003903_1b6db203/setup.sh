#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg build-essential cmake
    pip3 install pytest

    mkdir -p /app

    # Generate the video fixture (60 fps, 150 frames = 2.5 seconds)
    ffmpeg -f lavfi -i testsrc=duration=2.5:size=320x240:rate=60 -pix_fmt yuv420p /app/touch_recording.mp4

    # Create and compile the oracle smoother
    cat << 'EOF' > /app/oracle_smoother.cpp
#include <iostream>
#include <iomanip>

int main() {
    double alpha = 2.0 / (60.0 + 1.0);
    int max_frames = 150;
    int count = 0;
    double x, y;
    double sx = 0, sy = 0;
    bool first = true;

    while (std::cin >> x >> y) {
        if (count >= max_frames) break;
        if (first) {
            sx = x;
            sy = y;
            first = false;
        } else {
            sx = alpha * x + (1.0 - alpha) * sx;
            sy = alpha * y + (1.0 - alpha) * sy;
        }
        std::cout << std::fixed << std::setprecision(4) << sx << " " << sy << "\n";
        count++;
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle_smoother.cpp -o /app/oracle_smoother
    rm /app/oracle_smoother.cpp
    chmod +x /app/oracle_smoother

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
