#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sed perl xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    python3 -c "
import os
os.makedirs('/home/user/artifacts', exist_ok=True)
open('/home/user/artifacts/app1.bin', 'wb').write(b'\x11\x22\x33\xDE\xAD\xBE\xEF\x00\x00\x44\x55')
open('/home/user/artifacts/app2.bin', 'wb').write(b'\xAA\xBB\xCC\xDD')
open('/home/user/artifacts/app3.bin', 'wb').write(b'\xDE\xAD\xBE\xEF\x00\x00\x12\x34\xDE\xAD\xBE\xEF\x00\x00')
"

    cat << 'EOF' > /home/user/artifacts/manifest.json
{
  "artifacts": [
    {
      "name": "app1.bin",
      "sha256": "dummy1"
    },
    {
      "name": "app2.bin",
      "sha256": "dummy2"
    },
    {
      "name": "app3.bin",
      "sha256": "dummy3"
    }
  ]
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
