#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cmake g++ make ffmpeg
pip3 install pytest

# Create library
mkdir -p /home/user/lib
cat << 'EOF' > /tmp/custom_filter.cpp
int apply_filter(int x) { return x * 2; }
EOF
g++ -shared -fPIC /tmp/custom_filter.cpp -o /home/user/lib/libcustom_filter.so

# Create video processor source
mkdir -p /home/user/src/video_processor
cat << 'EOF' > /home/user/src/video_processor/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(video_processor)
add_executable(vproc_bin main.cpp)
target_link_libraries(vproc_bin custom_filter)
EOF

cat << 'EOF' > /home/user/src/video_processor/main.cpp
#include <iostream>
extern int apply_filter(int x);
int main() {
    std::cout << "Filtered: " << apply_filter(42) << std::endl;
    return 0;
}
EOF

# Create corpus directories and files
mkdir -p /app/corpus/clean /app/corpus/evil

for i in $(seq 1 50); do
  cat << EOF > /app/corpus/clean/safe_$i.conf
server {
    listen 80;
    location /safe$i {
        proxy_pass http://backend$i;
    }
}
EOF

  if [ $((i % 2)) -eq 0 ]; then
    cat << EOF > /app/corpus/evil/evil_$i.conf
server {
    listen 80;
    location /evil$i {
        proxy_pass http://backend$i/../secret;
    }
}
EOF
  else
    cat << EOF > /app/corpus/evil/evil_$i.conf
server {
    listen 8080;
    location /evil$i {
        proxy_pass http://backend$i;
    }
}
EOF
  fi
done

# Generate video fixture
ffmpeg -f lavfi -i color=c=black:s=320x240:d=30:r=1 \
  -vf "drawbox=x=0:y=0:w=50:h=50:color=white:t=fill:enable='between(t,27,27.9)'" \
  -c:v libx264 -y /app/test_sequence.mp4

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
