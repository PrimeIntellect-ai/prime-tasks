#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/math_util.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <algorithm>
#include <string>
#include <cstdint>
#include <cstring>

struct Point {
    int32_t id;
    float x;
    float y;
    float z;
    float distance;
};

// Base64 decode
std::vector<uint8_t> decode_base64(const std::string& val) {
    std::vector<int> T(256,-1);
    for(int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 
    int valb=-8;
    int vala=0;
    std::vector<uint8_t> out;
    for(uint8_t c : val) {
        if(T[c] == -1) break;
        vala = (vala<<6) + T[c];
        valb += 6;
        if(valb>=0) {
            out.push_back(char((vala>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}

bool comparePoints(const Point& a, const Point& b) {
    // BUG 1: Strict weak ordering violation
    return a.distance <= b.distance;
}

int main(int argc, char* argv[]) {
    if(argc != 3) return 1;

    std::ifstream in(argv[1]);
    std::string b64_str((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    in.close();

    std::vector<uint8_t> bin_data = decode_base64(b64_str);
    size_t num_points = bin_data.size() / sizeof(Point);

    // BUG 2 & 3: Memory bugs
    Point* points = new Point[num_points - 1]; // Buffer overflow
    memcpy(points, bin_data.data(), bin_data.size()); // Writes past allocated memory

    for(size_t i=0; i<num_points; i++) {
        // BUG 4: Uninitialized variable
        float dist;
        dist = std::sqrt(points[i].x * points[i].x + points[i].y * points[i].y + points[i].z * points[i].z);
        points[i].distance = dist;
    }

    std::sort(points, points + num_points, comparePoints);

    std::ofstream out(argv[2]);
    for(size_t i=0; i<num_points; i++) {
        out << points[i].id << "," << points[i].distance << "\n";
    }
    out.close();

    // BUG 3: Wrong delete
    delete points;
    return 0;
}
EOF

    python3 -c '
import struct
import base64
import math

points = [
    (1, 1.0, 2.0, 2.0),
    (2, 0.0, 0.0, 0.0),
    (3, 3.0, 4.0, 0.0),
    (4, 10.0, 0.0, 0.0),
    (5, 5.0, 5.0, 5.0)
]

binary_data = b""
expected = []
for p in points:
    dist = math.sqrt(p[1]**2 + p[2]**2 + p[3]**2)
    expected.append((p[0], dist))
    binary_data += struct.pack("<iffff", p[0], p[1], p[2], p[3], 0.0)

with open("/home/user/data.b64", "w") as f:
    f.write(base64.b64encode(binary_data).decode("ascii"))

expected.sort(key=lambda x: x[1])
with open("/home/user/expected.csv", "w") as f:
    for e in expected:
        f.write(f"{e[0]},{e[1]:.6g}\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
