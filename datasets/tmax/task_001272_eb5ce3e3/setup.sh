#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk
pip3 install pytest

# Generate video
mkdir -p /app
ffmpeg -f lavfi -i color=c=black:s=320x240:r=10:d=10 \
  -vf "drawbox=x=0:y=0:w=50:h=50:color=white:t=fill:enable='eq(n,25)+eq(n,42)+eq(n,88)'" \
  -c:v libx264 -pix_fmt yuv420p /app/incident_dashboard.mp4

# Generate corpus
mkdir -p /app/corpus/clean /app/corpus/evil

# Clean log 1
cat << 'EOF' > /app/corpus/clean/log1.log
100 A B 10
100 B C 15
100 C D 20
101 D A 5
EOF

# Clean log 2
cat << 'EOF' > /app/corpus/clean/log2.log
200 X Y 5
200 Y Z 10
201 Z X 15
EOF

# Evil log 1
cat << 'EOF' > /app/corpus/evil/log1.log
300 A B 10
300 B C 15
300 C A 20
301 A D 5
EOF

# Evil log 2
cat << 'EOF' > /app/corpus/evil/log2.log
405 P Q 12
405 X Y 1
405 Y Z 2
405 Z X 3
406 Q R 5
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
