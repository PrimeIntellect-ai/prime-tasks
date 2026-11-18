#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk bc espeak ffmpeg
    pip3 install pytest SpeechRecognition pydub

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/issue_42.wav "Please update the v2 schema migration. The ProcessRequest message needs a repeated int32 field named data, an int32 field named multiplier, and an int32 field named shift. The ProcessResponse needs a repeated int32 field named result. The required mathematical operation is: for every element in the data array, first add the shift value, then multiply that sum by the multiplier, and finally compute the modulo 256 of that product."

    # Create directories
    mkdir -p /home/user/math_service/proto

    # Create broken proto file
    cat << 'EOF' > /home/user/math_service/proto/service.proto
syntax = "proto3";

package math_service;

service SignalProcessor {
  rpc Process (ProcessRequest) returns (ProcessResponse);
}

// TODO: update based on audio memo
message ProcessRequest {
  repeated int32 data = 1;
}

message ProcessResponse {
}
EOF

    # Create initial broken process script
    cat << 'EOF' > /home/user/math_service/process.sh
#!/bin/bash
# TODO: Implement math logic from issue 42
cat -
EOF
    chmod +x /home/user/math_service/process.sh

    # Create the oracle
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys, json

try:
    req = json.load(sys.stdin)
    data = req.get('data', [])
    multiplier = req.get('multiplier', 1)
    shift = req.get('shift', 0)

    res = [((x + shift) * multiplier) % 256 for x in data]
    print(json.dumps({"result": res}))
except Exception as e:
    sys.exit(1)
EOF
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
