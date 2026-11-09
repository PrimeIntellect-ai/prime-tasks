#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        protobuf-compiler \
        protobuf-compiler-grpc \
        libgrpc++-dev \
        libprotobuf-dev \
        make \
        g++

    pip3 install pytest

    mkdir -p /app
    echo "dummy audio data" > /app/audio_fixture.wav

    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
if [ "$1" == "/app/audio_fixture.wav" ]; then
    echo "Migration to C++ is complete and the legacy Python 2 loops are resolved."
else
    echo "Unknown audio"
fi
EOF
    chmod +x /usr/local/bin/whisper

    mkdir -p /home/user/workspace/test_corpora

    cat << 'EOF' > /home/user/workspace/test_corpora/clean_routes.txt
/v3/api/audio/transcribe/wav
/v3/api/audio/analyze/mp3?quality=high
/v3/api/audio/metadata/flac
EOF

    cat << 'EOF' > /home/user/workspace/test_corpora/evil_routes.txt
/v3/api/audio/transcribe/ogg
/v2/api/audio/transcribe/wav
/v3/api/audio/../transcribe/wav
/v3/api/audio/transcribe/wav%00
/v3/api/audio/delete/wav
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
