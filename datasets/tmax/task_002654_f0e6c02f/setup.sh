#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app/clean /app/evil

    # 1. Create worker.core with API key
    dd if=/dev/urandom of=/app/worker.core bs=1024 count=10 2>/dev/null
    echo "API_KEY=7f8b9c2a1d3e4f5a6b7c8d9e0f1a2b3c" >> /app/worker.core
    dd if=/dev/urandom bs=1024 count=10 >> /app/worker.core 2>/dev/null

    # 2. Create audio_processor.py with deadlock
    cat << 'EOF' > /app/audio_processor.py
import threading
import time

lock_a = threading.Lock()
lock_b = threading.Lock()

def decrypt(file_path, key):
    # Dummy decryption function
    with open(file_path, 'rb') as f:
        return f.read()

def thread1_task():
    with lock_a:
        time.sleep(0.1)
        with lock_b:
            pass

def thread2_task():
    with lock_b:
        time.sleep(0.1)
        with lock_a:
            pass

def process_batch():
    t1 = threading.Thread(target=thread1_task)
    t2 = threading.Thread(target=thread2_task)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
EOF

    # 3. Create math_filter.py with convergence failure
    cat << 'EOF' > /app/math_filter.py
def f(x):
    return x**3 - x

def df(x):
    # Derivative is 0 when x = sqrt(1/3) ~ 0.577
    return 3 * (x**2) - 1

def denoise_signal(x):
    # Basic Newton-Raphson implementation
    for _ in range(10):
        x_new = x - f(x)/df(x)
        x = x_new
    return x
EOF

    # 4. Create dummy audio files
    python3 -c "
import wave, struct

def make_wav(path, is_evil=False):
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        # Write dummy frames
        val = 1000 if is_evil else 0
        w.writeframes(struct.pack('<h', val))

make_wav('/app/reference_audio.wav')
for i in range(3):
    make_wav(f'/app/clean/clean_{i}.wav', is_evil=False)
    make_wav(f'/app/evil/evil_{i}.wav', is_evil=True)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
