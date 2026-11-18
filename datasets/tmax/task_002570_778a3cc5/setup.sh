#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg
    pip3 install pytest

    mkdir -p /home/user/service
    mkdir -p /app

    # Create a test video file using ffmpeg
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -pix_fmt yuv420p /app/video.mp4

    cat << 'EOF' > /home/user/service/reference.py
import subprocess
import sys

def get_peak_motion_frame(video_path):
    cmd = [
        'ffmpeg', '-i', video_path,
        '-f', 'image2pipe',
        '-pix_fmt', 'gray',
        '-vcodec', 'rawvideo', '-'
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    # Assume 320x240 resolution for the raw video output based on our standard internal test videos
    width = 320
    height = 240
    frame_size = width * height

    prev_frame = None
    max_diff = -1
    peak_frame_idx = -1
    current_idx = 1

    while True:
        raw_frame = process.stdout.read(frame_size)
        if not raw_frame or len(raw_frame) != frame_size:
            break

        if prev_frame is not None:
            diff = sum(abs(raw_frame[i] - prev_frame[i]) for i in range(frame_size))
            if diff > max_diff:
                max_diff = diff
                peak_frame_idx = current_idx

        prev_frame = raw_frame
        current_idx += 1

    return peak_frame_idx
EOF

    cat << 'EOF' > /home/user/service/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int analyze_video(const char* video_path) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "ffmpeg -i %s -f image2pipe -pix_fmt gray -vcodec rawvideo - 2>/dev/null", video_path);

    FILE* pipe = popen(cmd, "r");
    if (!pipe) return -1;

    int width = 320;
    int height = 240;
    int frame_size = width * height;

    unsigned char* prev_frame = NULL;
    unsigned char* curr_frame = malloc(frame_size);

    long long max_diff = -1;
    int peak_frame_idx = -1;
    int current_idx = 1;

    while (fread(curr_frame, 1, frame_size, pipe) == frame_size) {
        if (prev_frame != NULL) {
            long long diff = 0;
            // TODO: Implement the absolute difference calculation here
            // diff = ...

            if (diff > max_diff) {
                max_diff = diff;
                peak_frame_idx = current_idx;
            }
        }

        // Memory leak here: we allocate but never free previous frames
        prev_frame = malloc(frame_size);
        for (int i=0; i<frame_size; i++) prev_frame[i] = curr_frame[i];

        current_idx++;
    }

    pclose(pipe);
    return peak_frame_idx;
}
EOF

    cat << 'EOF' > /home/user/service/Makefile
all: analyzer.c
	gcc analyzer.c -o libanalyzer.so
EOF

    cat << 'EOF' > /home/user/service/server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import ctypes
import os

class AuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/peak_motion':
            auth_header = self.headers.get('Authorization')
            if auth_header != 'Bearer deploy_token_2024':
                self.send_response(401)
                self.end_headers()
                return

            lib = ctypes.CDLL(os.path.abspath('libanalyzer.so'))
            lib.analyze_video.restype = ctypes.c_int
            lib.analyze_video.argtypes = [ctypes.c_char_p]

            video_path = b'/app/video.mp4'
            result = lib.analyze_video(video_path)

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"peak_frame": result}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), AuthHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
