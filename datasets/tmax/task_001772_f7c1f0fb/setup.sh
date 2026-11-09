#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust, ffmpeg, espeak-ng
    apt-get install -y cargo rustc ffmpeg espeak-ng

    # Install whisper with CPU-only PyTorch to avoid massive downloads and timeouts
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper SpeechRecognition

    # Create directories
    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /app/eval_corpora/clean /app/eval_corpora/evil

    # Generate audio file
    espeak-ng -w /app/auditor_notes.wav "We are seeing a new class of attacks. The attacker injects XSS using 'javascript:' URIs in the url parameters, and they tamper with ELF binaries by modifying the '.note.gnu.build-id' section. You need to flag any JSON log containing 'javascript:' in the url, or any ELF integrity log where 'tampered_section' equals '.note.gnu.build-id'."

    # Generate JSON logs
    for i in $(seq 1 10); do
        cat <<EOF > /app/corpora/clean/log_${i}.json
{"timestamp": "2023-10-25T12:00:00Z", "event_type": "web_request", "data": {"url": "/search?q=hello", "headers": {"User-Agent": "Mozilla/5.0"}}}
EOF
        cat <<EOF > /app/corpora/clean/elf_${i}.json
{"timestamp": "2023-10-25T12:05:00Z", "event_type": "elf_integrity", "data": {"binary_path": "/usr/bin/sshd", "tampered_section": ".text"}}
EOF
        cat <<EOF > /app/corpora/evil/log_${i}.json
{"timestamp": "2023-10-25T12:00:00Z", "event_type": "web_request", "data": {"url": "javascript:alert(1)", "headers": {"User-Agent": "Mozilla/5.0"}}}
EOF
        cat <<EOF > /app/corpora/evil/elf_${i}.json
{"timestamp": "2023-10-25T12:05:00Z", "event_type": "elf_integrity", "data": {"binary_path": "/usr/bin/sshd", "tampered_section": ".note.gnu.build-id"}}
EOF
    done

    for i in $(seq 1 50); do
        cat <<EOF > /app/eval_corpora/clean/log_${i}.json
{"timestamp": "2023-10-25T12:00:00Z", "event_type": "web_request", "data": {"url": "/search?q=hello", "headers": {"User-Agent": "Mozilla/5.0"}}}
EOF
        cat <<EOF > /app/eval_corpora/clean/elf_${i}.json
{"timestamp": "2023-10-25T12:05:00Z", "event_type": "elf_integrity", "data": {"binary_path": "/usr/bin/sshd", "tampered_section": ".text"}}
EOF
        cat <<EOF > /app/eval_corpora/evil/log_${i}.json
{"timestamp": "2023-10-25T12:00:00Z", "event_type": "web_request", "data": {"url": "javascript:alert(1)", "headers": {"User-Agent": "Mozilla/5.0"}}}
EOF
        cat <<EOF > /app/eval_corpora/evil/elf_${i}.json
{"timestamp": "2023-10-25T12:05:00Z", "event_type": "elf_integrity", "data": {"binary_path": "/usr/bin/sshd", "tampered_section": ".note.gnu.build-id"}}
EOF
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
