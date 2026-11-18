#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq ffmpeg build-essential time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/rate_limiter
    cat << 'EOF' > /home/user/rate_limiter/rl_check.c
int main(int argc, char *argv[]) {
    if (strlen(argv[1]) != 10) return 1;
    for(int i=0; i<10; i++) {
        if(!isalnum(argv[1][i])) return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/rate_limiter/Makefile
rl_check: rl_check.c
    gcc -o rl_check rl_check.c
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate dummy video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/dashcam.mp4

    cat << 'EOF' > /app/master_job.json
{
  "video": "dashcam.mp4",
  "timestamp": "00:00:05",
  "filters": "scale=640x480",
  "token": "A1B2C3D4E5"
}
EOF

    # Generate 10 clean corpus files
    for i in $(seq 1 10); do
cat << EOF > /app/corpus/clean/clean_$i.json
{
  "video": "vid_${i}.mp4",
  "timestamp": "00:00:15",
  "filters": "scale=320,vflip",
  "token": "A1B2C3D4E5"
}
EOF
    done

    # Generate 15 evil corpus files
    for i in $(seq 1 15); do
cat << EOF > /app/corpus/evil/evil_$i.json
{
  "video": "../../../etc/passwd",
  "timestamp": "00:00:15",
  "filters": "vflip; rm -rf /",
  "token": "INVALID_TOKEN_123"
}
EOF
    done

    chmod -R 777 /home/user
    chmod -R 777 /app
