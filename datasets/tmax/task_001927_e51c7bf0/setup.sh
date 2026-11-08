#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev ffmpeg gcc
pip3 install pytest

mkdir -p /home/user/steg_extractor
mkdir -p /app

cat << 'EOF' > /home/user/steg_extractor/setup.py
from distutils.core import setup, Extension

module1 = Extension('steg', sources = ['steg.c'])

setup (name = 'steg_extractor',
       version = '1.0',
       description = 'Extracts stego',
       ext_modules = [module1])
EOF

cat << 'EOF' > /home/user/steg_extractor/steg.c
#include <Python.h>

int extract_bit(const unsigned char* frame, int width, int height) {
    // NAIVE ALGORITHM: Just read the first pixel's LSB
    return frame[0] & 1;
}

static PyObject* steg_decode_frame(PyObject* self, PyObject* args) {
    const unsigned char* frame_data;
    int length;
    int width, height;

    if (!PyArg_ParseTuple(args, "s#ii", &frame_data, &length, &width, &height))
        return NULL;

    int bit = extract_bit(frame_data, width, height);
    return Py_BuildValue("i", bit);
}

static PyMethodDef StegMethods[] = {
    {"decode_frame",  steg_decode_frame, METH_VARARGS, "Decode a frame."},
    {NULL, NULL, 0, NULL}
};

void initsteg(void) {
    (void) Py_InitModule("steg", StegMethods);
}
EOF

cat << 'EOF' > /home/user/steg_extractor/process.py
import sys
import steg

def main():
    width = 640
    height = 480
    frame_size = width * height

    while True:
        frame = sys.stdin.read(frame_size)
        if len(frame) < frame_size:
            break
        bit = steg.decode_frame(frame, width, height)
        sys.stdout.write(str(bit))

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /tmp/generate_video.py
import subprocess

truth = "1010101110001100101011110000111100110101010001110010101011110000111100110101010001110010101011110000"
width = 640
height = 480

cmd = [
    'ffmpeg', '-y', '-f', 'rawvideo', '-pixel_format', 'gray',
    '-video_size', f'{width}x{height}', '-framerate', '10',
    '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/evidence.mp4'
]

p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
for bit in truth:
    frame = bytearray([128] * (width * height))
    val = 255 if bit == '1' else 0
    for y in range(10):
        for x in range(10):
            frame[y * width + x] = val
    p.stdin.write(frame)
p.stdin.close()
p.wait()
EOF

python3 /tmp/generate_video.py
rm /tmp/generate_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
