#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        ffmpeg \
        libavformat-dev \
        libavcodec-dev \
        libavutil-dev \
        libswscale-dev \
        libgl1 \
        libglib2.0-0

    pip3 install pytest pybind11 opencv-python scikit-image numpy

    mkdir -p /workspace/vid_project
    mkdir -p /app

    # Generate a test video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 /app/test_video.mp4 -y

    cat << 'EOF' > /workspace/vid_project/setup.py
import os
from setuptools import setup, Extension
import pybind11

def get_libs(conf_path):
    libs = []
    with open(conf_path, 'r') as f:
        for line in f:
            # Buggy parsing: doesn't handle inline comments properly
            if line.strip() and not line.startswith('#'):
                libs.append(line.strip())
    return libs

ext_modules = [
    Extension(
        'video_extractor',
        ['extractor.cpp'],
        include_dirs=[pybind11.get_include()],
        libraries=get_libs('libs.conf'),
        language='c++'
    ),
]

setup(
    name='video_extractor',
    ext_modules=ext_modules,
)
EOF

    cat << 'EOF' > /workspace/vid_project/libs.conf
avformat
avcodec # The codec library
avutil
swscale
EOF

    cat << 'EOF' > /workspace/vid_project/extractor.cpp
#include <pybind11/pybind11.h>
#include <string>
#include <cstdlib>

// Bug: missing extern "C"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

namespace py = pybind11;

void extract_frames(const std::string& video_path, const std::string& out_dir) {
    // Force linker to need these symbols
    AVFormatContext* ctx = avformat_alloc_context();
    if (ctx) {
        avformat_free_context(ctx);
    }

    // Core extraction logic
    std::string cmd = "ffmpeg -i " + video_path + " -vf \"select='eq(n,10)+eq(n,20)+eq(n,30)'\" -vsync 0 " + out_dir + "/frame_%d.jpg -y -loglevel quiet";
    std::system(cmd.c_str());
}

PYBIND11_MODULE(video_extractor, m) {
    m.def("extract_frames", &extract_frames, "Extract frames 10, 20, 30");
}
EOF

    cat << 'EOF' > /workspace/vid_project/run_pipeline.py
import sys
import os
import video_extractor

def main():
    if len(sys.argv) < 3:
        print("Usage: python run_pipeline.py <video_path> <out_dir>")
        sys.exit(1)

    video_path = sys.argv[1]
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    video_extractor.extract_frames(video_path, out_dir)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /workspace
    chmod -R 777 /app
    chmod -R 777 /home/user
