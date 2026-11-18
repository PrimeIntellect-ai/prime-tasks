#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask fastapi uvicorn requests SpeechRecognition soundfile

    mkdir -p /app

    # Create the config_events.jsonl file with the broken unicode surrogate
    cat << 'EOF' > /app/config_events.jsonl
{"node_id": "A", "timestamp": 10, "operation": "add", "vector": [10, 20, 30], "comment": "init"}
{"node_id": "B", "timestamp": 5, "operation": "add", "vector": [500, 500, 500], "comment": "init"}
{"node_id": "C", "timestamp": 20, "operation": "add", "vector": [1, 2, 3], "comment": "broken unicode: \ud800"}
{"node_id": "A", "timestamp": 15, "operation": "multiply", "vector": [2, 1, -1], "comment": "scale"}
{"node_id": "B", "timestamp": 12, "operation": "multiply", "vector": [3, 3, 3], "comment": "boom"}
{"node_id": "C", "timestamp": 25, "operation": "add", "vector": [4, 5, 6], "comment": "more"}
EOF

    # Create a dummy wav file (to be overridden by the test suite, but needed for initial state)
    python3 -c "
import wave, struct
with wave.open('/app/authorization_pin.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframes(struct.pack('<h', 0) * 44100)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
