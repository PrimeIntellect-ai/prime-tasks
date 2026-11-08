#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the instruction audio file
    espeak-ng -w /app/instructions.wav "We are seeing a lot of attacks from a specific subnet. You need to block any request where the source IP falls within the 10.42.0.0/16 subnet AND the destination port is exactly 8080. Everything else should be allowed."

    # Generate clean corpus
    for i in $(seq 1 25); do
        cat <<EOF > /app/corpus/clean/clean_ip_$i.json
{"src_ip": "10.42.0.$i", "dst_port": 8081, "protocol": "tcp", "payload": "clean"}
EOF
        cat <<EOF > /app/corpus/clean/clean_port_$i.json
{"src_ip": "192.168.1.$i", "dst_port": 8080, "protocol": "tcp", "payload": "clean"}
EOF
    done

    # Generate evil corpus
    for i in $(seq 1 50); do
        cat <<EOF > /app/corpus/evil/evil_$i.json
{"src_ip": "10.42.0.$i", "dst_port": 8080, "protocol": "tcp", "payload": "evil"}
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
