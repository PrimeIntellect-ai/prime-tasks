#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Setup workspace and create the zip file
    python3 -c '
import os
import zipfile

workspace = "/home/user/workspace"
os.makedirs(workspace, exist_ok=True)
os.makedirs(f"{workspace}/doc_processor", exist_ok=True)

zip_path = f"{workspace}/legacy_docs.zip"
with zipfile.ZipFile(zip_path, "w") as zf:
    zf.writestr("docs/intro.txt", "[HEADER] Introduction\nThis is [B]very[/B] important.")
    zf.writestr("docs/setup.txt", "[HEADER] Setup\nFollow the instructions.")
    info = zipfile.ZipInfo("../secret_config.txt")
    zf.writestr(info, "MALICIOUS CONTENT")
'

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure rust is available for the user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    # Set permissions
    chmod -R 777 /home/user
