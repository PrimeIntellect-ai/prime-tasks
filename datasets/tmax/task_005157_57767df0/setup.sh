#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        multimon-ng \
        nginx \
        openssh-server \
        openssh-client \
        cron \
        golang \
        sudo

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create /app and generate audio file
    mkdir -p /app
    cat << 'EOF' > /tmp/gen_audio.py
import wave, math, struct
freqs = {'7':(852,1209), '3':(697,1477), '9':(852,1477), '2':(697,1336), '5':(770,1336)}
sample_rate = 8000
with wave.open('/app/voicemail.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for d in '73925':
        f1, f2 = freqs[d]
        for i in range(int(sample_rate * 0.2)):
            t = float(i) / sample_rate
            val = int(16000 * (math.sin(2*math.pi*f1*t) + math.sin(2*math.pi*f2*t)))
            w.writeframesraw(struct.pack('<h', val))
        for i in range(int(sample_rate * 0.1)):
            w.writeframesraw(struct.pack('<h', 0))
EOF
    python3 /tmp/gen_audio.py

    # Nginx configuration
    mkdir -p /home/user/nginx
    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location /pin {
            proxy_pass http://unix:/tmp/wrong_path.sock;
        }
    }
}
EOF

    # Configure SSH daemon
    mkdir -p /run/sshd

    # Ensure services start when bash is invoked (useful for tests)
    echo "service ssh start > /dev/null 2>&1" >> /etc/bash.bashrc
    echo "service cron start > /dev/null 2>&1" >> /etc/bash.bashrc

    # Permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod 777 /tmp
