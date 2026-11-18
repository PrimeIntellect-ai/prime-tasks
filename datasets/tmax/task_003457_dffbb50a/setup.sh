#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        gcc \
        make \
        fonts-liberation \
        libsm6 \
        libxext6 \
        libgl1-mesa-glx

    pip3 install pytest Pillow opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Create Python script to generate video frames
    cat << 'EOF' > /tmp/gen_frames.py
import os
import random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)
edges = []
for i in range(250):
    u = random.randint(1, 100)
    v = random.randint(1, 100)
    edges.append((u, v))

os.makedirs("/tmp/frames", exist_ok=True)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 32)
except:
    font = ImageFont.load_default()

for i in range(50):
    img = Image.new('RGB', (800, 600), color=(255, 255, 255))
    d = ImageDraw.Draw(img)
    y = 50
    for j in range(5):
        idx = i * 5 + j
        text = f"INSERT_EDGE: {edges[idx][0]} -> {edges[idx][1]}"
        d.text((50, y), text, fill=(0, 0, 0), font=font)
        y += 80
    img.save(f"/tmp/frames/frame_{i:03d}.png")
EOF

    python3 /tmp/gen_frames.py
    ffmpeg -framerate 5 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/transaction_monitor.mp4

    # Create naive query_engine.c
    cat << 'EOF' > /home/user/query_engine.c
#include <stdio.h>
#include <stdlib.h>

struct Edge {
    int u;
    int v;
};

int main() {
    FILE *f = fopen("/home/user/edges.csv", "r");
    if (!f) {
        printf("Could not open edges.csv\n");
        return 1;
    }

    struct Edge edges[100000];
    int num_edges = 0;
    while (fscanf(f, "%d,%d", &edges[num_edges].u, &edges[num_edges].v) == 2) {
        num_edges++;
    }
    fclose(f);

    int path_counts[1000] = {0};
    int max_node = 0;

    // Naive O(E^2) nested loop to find paths of length 2
    for (int i = 0; i < num_edges; i++) {
        for (int j = 0; j < num_edges; j++) {
            if (edges[i].v == edges[j].u) {
                int a = edges[i].u;
                path_counts[a]++;
                if (a > max_node) max_node = a;
            }
        }
    }

    // Rolling sum
    int rolling_sum = 0;
    for (int i = 0; i <= max_node; i++) {
        if (path_counts[i] > 0) {
            int sum = 0;
            for (int k = (i - 2 >= 0 ? i - 2 : 0); k <= i; k++) {
                sum += path_counts[k];
            }
            printf("%d,%d\n", i, sum);
        }
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 777 /app/transaction_monitor.mp4
