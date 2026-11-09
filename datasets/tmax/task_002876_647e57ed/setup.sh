#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make patch protobuf-compiler
pip3 install pytest grpcio grpcio-tools Pillow

mkdir -p /app
cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "gRPC Port: 50051", fill=(0,0,0))
d.text((10,50), "Rate Limit: 120 req/min", fill=(0,0,0))
img.save('/app/build_arch.png')
EOF
python3 /tmp/make_image.py

mkdir -p /home/user/libmobilecore
cat << 'EOF' > /home/user/libmobilecore/core.h
#ifndef CORE_H
#define CORE_H

struct CacheData {
    char type;
    // ABI issue: padding
    int value;
};

extern "C" {
    int process_cache_key(const char* key);
}

#endif
EOF

cat << 'EOF' > /home/user/libmobilecore/core.cpp
#include "core.h"
#include <cstring>

int process_cache_key(const char* key) {
    if (!key) return 0;
    return strlen(key);
}
EOF

cat << 'EOF' > /home/user/libmobilecore/Makefile
all: libmobilecore.so

libmobilecore.so: core.cpp
	mkdir -p build
	g++ -shared -fPIC -o build/libmobilecore.so core.cpp

clean:
	rm -rf build
EOF

cat << 'EOF' > /home/user/libmobilecore/fix_abi.patch
--- core.h
+++ core.h
@@ -3,8 +3,8 @@

 struct CacheData {
+    int value;
     char type;
-    // ABI issue: padding
-    int value;
 };

 extern "C" {
EOF

cat << 'EOF' > /home/user/build_cache.proto
syntax = "proto3";

service BuildCache {
  rpc CheckCache (CacheRequest) returns (CacheResponse) {}
}

message CacheRequest {
  string key = 1;
}

message CacheResponse {
  bool hit = 1;
}
EOF

cat << 'EOF' > /home/user/diff_parser.py
import sys
import json

def parse_diff(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    summary = {}
    current_file = None

    for line in lines:
        if line.startswith('+++ '):
            current_file = line[4:].strip()
            if current_file not in summary:
                summary[current_file] = {'additions': 0, 'deletions': 0}
        elif line.startswith('+') and not line.startswith('+++'):
            if current_file:
                summary[current_file]['additions'] = summary[current_file].get('additions', 0) + 1
        elif line.startswith('-') and not line.startswith('---'):
            if current_file:
                summary[current_file]['deletions'] = summary[current_file].get('deletions', 0) + 1

    with open('/home/user/diff_summary.json', 'w') as f:
        json.dump(summary, f)

if __name__ == '__main__':
    parse_diff('/home/user/large_build.diff')
EOF

cat << 'EOF' > /tmp/make_diff.py
with open('/home/user/large_build.diff', 'w') as f:
    for i in range(1000):
        f.write(f"--- a/file_{i}.txt\n")
        f.write(f"+++ b/file_{i}.txt\n")
        for j in range(100):
            f.write(f"+ added line {j}\n")
            f.write(f"- removed line {j}\n")
EOF
python3 /tmp/make_diff.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
