#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user

    # Create a dummy binary file containing the guest JWT.
    guest_header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    guest_payload=$(echo -n '{"role":"guest"}' | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    guest_sig="dummy_signature_bytes_here"
    guest_jwt="${guest_header}.${guest_payload}.${guest_sig}"

    # Create a fake ELF-like binary
    head -c 1024 /dev/urandom > /home/user/auth_client
    echo -n "Bearer $guest_jwt" >> /home/user/auth_client
    head -c 512 /dev/urandom >> /home/user/auth_client
    chmod +x /home/user/auth_client

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
