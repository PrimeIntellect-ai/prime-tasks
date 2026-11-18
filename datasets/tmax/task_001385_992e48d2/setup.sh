#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/topo_sort.py
#!/usr/bin/env python3
import sys
import math

def solve():
    if len(sys.argv) < 2:
        return
    s = sys.argv[1]
    N = int(math.isqrt(len(s)))
    adj = []
    for i in range(N):
        adj.append([int(x) for x in s[i*N:(i+1)*N]])

    in_degree = [0]*N
    for i in range(N):
        for j in range(N):
            if adj[i][j] == 1:
                in_degree[j] += 1

    import heapq
    q = []
    for i in range(N):
        if in_degree[i] == 0:
            heapq.heappush(q, i)

    res = []
    while q:
        u = heapq.heappop(q)
        res.append(u)
        for v in range(N):
            if adj[u][v] == 1:
                in_degree[v] -= 1
                if in_degree[v] == 0:
                    heapq.heappush(q, v)

    if len(res) == N:
        print(" ".join(map(str, res)))
    else:
        print("CYCLE DETECTED")

if __name__ == '__main__':
    solve()
EOF
    chmod +x /opt/oracle/topo_sort.py
    ln -s /opt/oracle/topo_sort.py /opt/oracle/topo_sort

    bash -c '
    mkdir -p /app
    cd /tmp
    MATRIX_STRING="0110000000001100000000011000000000110000000001100000000011000000000110000000001100000000010000000000"
    for i in {0..99}; do
        char="${MATRIX_STRING:$i:1}"
        if [ "$char" == "1" ]; then
            color="white"
        else
            color="black"
        fi
        convert -size 64x64 canvas:$color frame_$(printf "%03d" $i).png
    done
    ffmpeg -framerate 10 -i frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/pipeline_state.mp4
    rm frame_*.png
    '

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
