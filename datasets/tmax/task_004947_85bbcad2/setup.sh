#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make espeak ffmpeg
    pip3 install pytest grpcio grpcio-tools protobuf

    mkdir -p /app

    # Generate a dummy WAV file to satisfy the initial state test
    python3 -c "import wave, struct; f=wave.open('/app/transmission.wav', 'w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); f.writeframesraw(struct.pack('<h', 0)*44100); f.close()"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
