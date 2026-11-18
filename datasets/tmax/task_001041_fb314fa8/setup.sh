#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make gdb ffmpeg libavformat-dev libavcodec-dev libavutil-dev libswscale-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user/src /home/user/samples

    # Create dummy incident video
    ffmpeg -f lavfi -i color=c=green:s=100x100:d=3 -c:v libx264 /app/incident_001.mp4

    # Create video_processor.cpp
    cat << 'EOF' > /home/user/src/video_processor.cpp
#include <iostream>
#include <vector>
// missing #include <cassert>

void process_frame(const std::vector<unsigned char>& frame, int width, int height) {
    long long sum_r = 0, sum_g = 0, sum_b = 0;
    for (size_t i = 0; i < frame.size(); i += 3) {
        sum_r += frame[i];
        sum_g += frame[i+1];
        sum_b += frame[i+2];
    }

    if (sum_r == 0 && sum_b == 0 && sum_g > 0) {
        // Bug here: division by zero
        int allocation_size = 1000 / sum_r;
        std::cout << "Allocating " << allocation_size << " bytes\n";
    }
}

int main() {
    std::vector<unsigned char> frame(100 * 100 * 3, 0);
    // simulate pure green
    for (size_t i = 0; i < frame.size(); i += 3) {
        frame[i+1] = 255;
    }
    process_frame(frame, 100, 100);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/src/Makefile
video_processor: video_processor.cpp
	g++ -g -O0 video_processor.cpp -o video_processor -lffmpeg
EOF

    # Generate core dump
    cd /home/user/src
    g++ -g -O0 video_processor.cpp -o video_processor_temp || true
    ulimit -c unlimited
    ./video_processor_temp || true
    # If core dump is not generated, create a dummy one
    if [ ! -f core ]; then
        echo "dummy core dump" > /home/user/core
    else
        mv core /home/user/core
    fi
    rm -f video_processor_temp

    # Create dummy samples
    ffmpeg -f lavfi -i color=c=red:s=100x100:d=1 -c:v libx264 /home/user/samples/sample1.mp4
    ffmpeg -f lavfi -i color=c=green:s=100x100:d=1 -c:v libx264 /home/user/samples/sample2.mp4

    # Create dummy corpus
    for i in {1..5}; do
        ffmpeg -f lavfi -i color=c=green:s=100x100:d=1 -c:v libx264 /app/corpus/evil/evil_$i.mp4
        ffmpeg -f lavfi -i color=c=blue:s=100x100:d=1 -c:v libx264 /app/corpus/clean/clean_$i.mp4
    done

    chmod -R 777 /home/user
    chmod -R 777 /app
