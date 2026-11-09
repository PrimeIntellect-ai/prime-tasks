#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/manifest.json
{
  "artifacts": [
    {"name": "base", "platforms": ["linux", "windows", "mac"], "deps": []},
    {"name": "crypto", "platforms": ["linux", "windows"], "deps": ["base"]},
    {"name": "gui_mac", "platforms": ["mac"], "deps": ["base"]},
    {"name": "gui_x11", "platforms": ["linux"], "deps": ["base"]},
    {"name": "app", "platforms": ["linux", "windows", "mac"], "deps": ["crypto", "gui_mac", "gui_x11", "base"]}
  ]
}
EOF

    chmod -R 777 /home/user
