#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /app/vendored/patch_manager
    cat << 'EOF' > /app/vendored/patch_manager/patcher.py
import diflib # Bug 1: typo in difflib

def apply_diff(original_text, patch_text):
    return "" # Bug 2: hardcoded return
    # The agent will need to implement or fix a simple diff applier
    # For a real env, we'd include actual diff application logic here.
    # To keep it verifiable and simple:
    if "Universe" in patch_text:
        return original_text.replace("World", "Universe")
    return original_text
EOF

    cat << 'EOF' > /app/vendored/patch_manager/__init__.py
from .patcher import apply_diff
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
