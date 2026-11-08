#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip g++ build-essential
    pip3 install pytest

    mkdir -p /app/corpus_raw/clean /app/corpus_raw/evil

    # Create clean files
    echo -n "user%3Djohn%26id%3D123" > /app/corpus_raw/clean/clean_01.txt
    echo -n "file%3Dreport_final.pdf" > /app/corpus_raw/clean/clean_02.txt
    echo -n "search%3Dapples%2Band%2Boranges" > /app/corpus_raw/clean/clean_03.txt

    # Create evil files
    echo -n "file%3D..%2F..%2F..%2Fetc%2Fpasswd" > /app/corpus_raw/evil/evil_01.txt
    echo -n "user%3Dadmin%3B%20rm%20-rf%20%2F" > /app/corpus_raw/evil/evil_02.txt
    echo -n "id%3D123%20%7C%20cat%20%2Fetc%2Fshadow" > /app/corpus_raw/evil/evil_03.txt

    # Create password protected zip
    cd /app/corpus_raw
    zip -r -P 739284 /app/audit_logs.zip clean evil
    cd /
    rm -rf /app/corpus_raw

    # Generate DTMF voicemail.wav
    cat << 'EOF' > /tmp/gen_dtmf.py
import wave, math, struct
sample_rate = 8000
duration = 0.5
frequencies = {
    '7': (852, 1209), '3': (697, 1477), '9': (852, 1477),
    '2': (697, 1336), '8': (852, 1336), '4': (770, 1209)
}
pin = "739284"
with wave.open('/app/voicemail.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for digit in pin:
        f1, f2 = frequencies[digit]
        for i in range(int(sample_rate * duration)):
            t = float(i) / sample_rate
            value = int(32767.0 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
            f.writeframesraw(struct.pack('<h', value))
        # Silence
        for i in range(int(sample_rate * 0.1)):
            f.writeframesraw(struct.pack('<h', 0))
EOF
    python3 /tmp/gen_dtmf.py
    rm /tmp/gen_dtmf.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
