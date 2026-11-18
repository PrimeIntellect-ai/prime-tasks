#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iproute2 procps
    pip3 install pytest pyinstaller

    mkdir -p /app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create the auth_daemon source
    cat << 'EOF' > /app/daemon.py
import socket
import sys
import base64
import hmac
import hashlib
import random
import threading

def handle_client(conn):
    try:
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(1024)
            if not chunk:
                break
            data += chunk
        line = data.split(b"\n")[0]
        decoded = base64.b64decode(line).decode('utf-8')
        parts = decoded.split('|')
        if len(parts) == 4:
            msg = f"{parts[0]}|{parts[1]}|{parts[2]}".encode('utf-8')
            key = b"B@ckd00r_M@st3r_K3y_2023!"
            h = hmac.new(key, msg, hashlib.sha256).hexdigest()
            if h == parts[3]:
                conn.sendall(b"VALID\n")
            else:
                conn.sendall(b"INVALID\n")
        else:
            conn.sendall(b"INVALID\n")
    except Exception:
        conn.sendall(b"INVALID\n")
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    for _ in range(1000):
        port = random.randint(8000, 9000)
        try:
            s.bind(('127.0.0.1', port))
            break
        except:
            pass
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn,), daemon=True).start()

if __name__ == "__main__":
    main()
EOF

    # Compile the daemon into a stripped binary
    cd /app
    pyinstaller --onefile daemon.py
    mv dist/daemon /app/auth_daemon
    strip /app/auth_daemon
    chmod +x /app/auth_daemon
    rm -rf build dist daemon.py daemon.spec

    # Generate the corpora and wordlist
    cat << 'EOF' > /app/setup_corpus.py
import os
import random
import uuid
import base64
import hmac
import hashlib

def gen_token(username, key, pwd_hash, valid_sig=True):
    msg = f"{username}|{key}|{pwd_hash}"
    if valid_sig:
        sig = hmac.new(b"B@ckd00r_M@st3r_K3y_2023!", msg.encode(), hashlib.sha256).hexdigest()
    else:
        sig = "invalid_signature_hex_000000000000000000000000"
    token = f"{msg}|{sig}"
    return base64.b64encode(token.encode()).decode()

words = ["password123", "admin", "letmein", "qwerty"] + [f"pass{i}" for i in range(100)]
with open('/home/user/wordlist.txt', 'w') as f:
    f.write("\n".join(words))

# Clean
for i in range(1, 51):
    u = f"user{i}"
    k = random.choice(["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI", "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAI"])
    p = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
    t = gen_token(u, k, p, True)
    with open(f'/home/user/corpus/clean/clean_{i:02d}.txt', 'w') as f:
        f.write(t)

# Evil
for i in range(1, 16):
    u = f"evil_sig_{i}"
    k = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI"
    p = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
    t = gen_token(u, k, p, False)
    with open(f'/home/user/corpus/evil/evil_{i:02d}.txt', 'w') as f:
        f.write(t)

for i in range(16, 31):
    u = f"evil_key_{i}"
    k = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB"
    p = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
    t = gen_token(u, k, p, True)
    with open(f'/home/user/corpus/evil/evil_{i:02d}.txt', 'w') as f:
        f.write(t)

for i in range(31, 51):
    u = f"evil_pwd_{i}"
    k = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI"
    w = random.choice(words)
    p = hashlib.sha256(w.encode()).hexdigest()
    t = gen_token(u, k, p, True)
    with open(f'/home/user/corpus/evil/evil_{i:02d}.txt', 'w') as f:
        f.write(t)
EOF

    python3 /app/setup_corpus.py
    rm /app/setup_corpus.py

    # Wrap python3 to ensure the daemon is running when tests/scripts are executed
    mv /usr/bin/python3 /usr/bin/python3.real
    cat << 'EOF' > /usr/bin/python3
#!/bin/bash
if ! pgrep -f auth_daemon > /dev/null; then
    /app/auth_daemon &
    sleep 0.5
fi
exec /usr/bin/python3.real "$@"
EOF
    chmod +x /usr/bin/python3

    # Create the user
    useradd -m -s /bin/bash user || true

    # Final permissions
    chmod -R 777 /home/user
