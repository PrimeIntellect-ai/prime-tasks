#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/upload_handler.py
import json
import base64

def xor_decrypt(hex_cipher, key="S3cr3tK3y"):
    cipher_bytes = bytes.fromhex(hex_cipher)
    key_bytes = key.encode()
    plain = bytearray()
    for i in range(len(cipher_bytes)):
        plain.append(cipher_bytes[i] ^ key_bytes[i % len(key_bytes)])
    return plain.decode()

def handle_upload(b64_payload):
    try:
        data = json.loads(base64.b64decode(b64_payload).decode())
        filename = data.get("filename")
        enc_content = data.get("content")

        # VULNERABILITY: No sanitization of filename! Path traversal possible.
        save_path = f"/home/user/uploads/{filename}"

        content = xor_decrypt(enc_content)

        with open(save_path, "w") as f:
            f.write(content)
        print(f"Saved {filename}")
    except Exception as e:
        print("Error")
EOF

    cat << 'EOF' > /home/user/incident_logs.txt
eyJmaWxlbmFtZSI6ICJub3JtYWxfZmlsZS50eHQiLCAiY29udGVudCI6ICIxYjQ1MTEwZTM3NTY0MzEzMDE0MjI2MTYxOTM0NTRmMTYwYzI3MWI0NTE2MDYxNzVlNTYxZTE2MWM1NTUyZTRiMWExZTEyMDM0MjU2In0=
eyJmaWxlbmFtZSI6ICIuLi8uLi9ldGMvcGFzc3dkIiwgImNvbnRlbnQiOiAiMzE0ZjRkMDYxMjI4MDMzMjE0NmIzZTEwMDMyMTRmMTEwYTRmNTE0ZDEyMjQxMzExMGE0ZDU0NGQ0MTQ0MTMxNCJ9
eyJmaWxlbmFtZSI6ICIuLi9zdG9sZW5fZGF0YS5jc3YiLCAiY29udGVudCI6ICIzNjZkMzA0ZDNlNGU0MDQwMWExYTFjMjY0YjAxNDg1MjEyMzQ1MzE2MTEwZDNiMGUxODc1NmIxZTNjNWEzOTM4MDI1NjMwMDgxZjJiMTI0ZDFmMTM1MTU3MWY1YzJiMTQwZDNiMGUxODc1NmIxZTIyNGEzYzM1M2U0YzU2MjQ0MTE1In0=
EOF

    chmod -R 777 /home/user
