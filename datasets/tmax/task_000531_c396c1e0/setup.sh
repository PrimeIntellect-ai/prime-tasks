#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg espeak
pip3 install pytest
pip3 install torch --index-url https://download.pytorch.org/whl/cpu
pip3 install openai-whisper

mkdir -p /app/c_src

cat << 'EOF' > /app/c_src/transform.c
#include <math.h>
int transform(int x) {
    return (int)(pow(x, 2) + 3*x - 5) % 100;
}
EOF

cat << 'EOF' > /app/c_src/Makefile
libtransform.so: transform.c
	gcc -shared -fPIC transform.c -o libtransform.so
EOF

cat << 'EOF' > /app/graph.json
{
  "A": ["B", "C"],
  "B": ["D"],
  "C": ["D", "E"],
  "D": ["F"],
  "E": ["F"],
  "F": []
}
EOF

cat << 'EOF' > /app/oracle_evaluator
#!/usr/bin/env python3
import sys, math
x = int(sys.argv[1])
transform_val = int(math.pow(x, 2) + 3*x - 5) % 100
result = (transform_val * 4) % 10007
print(result)
EOF
chmod +x /app/oracle_evaluator

espeak -w /app/architecture_notes.wav "To compute the final evaluation metric, you must combine the structural properties of the graph with the core transformation. First, pass the input value X into the C library's transform function. Take that result and multiply it by the number of nodes in the longest path of the directed acyclic graph provided in graph.json. Finally, take this product and apply modulo ten thousand and seven. Print this exact integer."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
