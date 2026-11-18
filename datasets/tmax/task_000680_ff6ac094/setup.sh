#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsndfile1

    # Install CPU-only PyTorch to avoid massive downloads and timeouts
    pip3 install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    pip3 install transformers sentence-transformers flask fastapi uvicorn soundfile librosa numpy requests pytest

    mkdir -p /app

    cat << 'EOF' > /app/intents.json
[
  {"intent_name": "password_reset", "description": "The user forgot their password and needs to reset it or cannot log in."},
  {"intent_name": "refund_request", "description": "The user is asking for their money back for a recent purchase."},
  {"intent_name": "cancel_subscription", "description": "The user wants to stop their ongoing subscription or membership."},
  {"intent_name": "speak_to_human", "description": "The user is frustrated and wants to talk to a real person or agent."}
]
EOF

    # Create a dummy valid 16kHz WAV file for the initial state
    python3 -c "import soundfile as sf; import numpy as np; sf.write('/app/support_call.wav', np.zeros(16000), 16000)"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
