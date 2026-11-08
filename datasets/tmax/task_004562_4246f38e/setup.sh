#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest flask cryptography

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/server.py
from flask import Flask, request, jsonify
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend
import os
import binascii

app = Flask(__name__)
SECRET_KEY = os.urandom(16)

def encrypt_aes_cbc(plaintext: bytes) -> tuple:
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(plaintext) + padder.finalize()
    cipher = Cipher(algorithms.AES(SECRET_KEY), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(padded_data) + encryptor.finalize()
    return iv, ciphertext

def decrypt_aes_cbc(iv: bytes, ciphertext: bytes) -> bytes:
    cipher = Cipher(algorithms.AES(SECRET_KEY), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    padded_data = decryptor.update(ciphertext) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(padded_data) + unpadder.finalize()

@app.route('/encrypt', methods=['POST'])
def encrypt():
    data = request.json.get('plaintext', '')
    if '<' in data or '>' in data:
        return jsonify({"error": "WAF Blocked: Malicious characters detected"}), 403

    iv, ciphertext = encrypt_aes_cbc(data.encode('utf-8'))
    token = f"{binascii.hexlify(iv).decode()}:{binascii.hexlify(ciphertext).decode()}"
    return jsonify({"token": token})

@app.route('/submit', methods=['POST'])
def submit():
    try:
        token = request.json.get('token', '')
        hex_iv, hex_ct = token.split(':')
        iv = binascii.unhexlify(hex_iv)
        ciphertext = binascii.unhexlify(hex_ct)

        plaintext = decrypt_aes_cbc(iv, ciphertext).decode('utf-8')

        if plaintext == '<svg onload=1>':
            with open('/tmp/success.log', 'w') as f:
                f.write('FLAG{cbc_b1t_fl1pp1ng_m4st3r}')
            return jsonify({"status": "success", "message": "Evasion successful!"})
        else:
            return jsonify({"status": "failed", "decrypted": plaintext})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

chmod -R 777 /home/user
