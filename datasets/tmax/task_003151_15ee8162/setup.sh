#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    # Install PyTorch CPU version to avoid massive CUDA downloads and timeouts, then whisper
    pip3 install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    # Create required directories
    mkdir -p /app/grader/evil
    mkdir -p /app/grader/clean

    # Generate the main voicemail file
    espeak -w /app/voicemail_99.wav "Attention. The new spam campaigns are aggressively using the words: 'cryptocurrency', 'timeshare', and 'viagra'. Please configure the filters immediately."

    # Generate evil corpus
    echo "This is just a text file, not a valid audio file." > /app/grader/evil/corrupt1.wav
    dd if=/dev/urandom of=/app/grader/evil/corrupt2.wav bs=1024 count=10
    espeak -w /app/grader/evil/spam_crypto.wav "You should invest in our new cryptocurrency platform."
    espeak -w /app/grader/evil/spam_timeshare.wav "Congratulations, you have been selected for a free timeshare."
    espeak -w /app/grader/evil/spam_viagra.wav "Get cheap viagra delivered to your door."

    # Generate clean corpus
    espeak -w /app/grader/clean/clean_maintenance.wav "Please call me back regarding the server maintenance."
    espeak -w /app/grader/clean/clean_meeting.wav "The quarterly review meeting is scheduled for tomorrow at ten AM."
    espeak -w /app/grader/clean/clean_lunch.wav "Are we still on for lunch today?"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
