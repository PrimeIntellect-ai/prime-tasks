#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    echo -n "malicious payload alpha data" > /home/user/evidence/payload_alpha.bin
    echo -n "malicious payload beta data" > /home/user/evidence/payload_beta.bin
    echo -n "fake image data" > /home/user/evidence/benign_image.png
    echo -n "random text" > /home/user/evidence/unknown.txt

    cat << 'EOF' > /home/user/server.log
{"ip": "10.0.0.1", "method": "POST", "path": "/upload?dir=../../tmp", "status": 200, "user_agent": "Mozilla/5.0 <script>alert(1)</script>", "headers": {"X-Payload-Hash": "18a66fbc6100c5c41da367ea82b4da677ff8f44ffc91b5c468e21151664d4cbb", "Host": "example.com"}}
{"ip": "10.0.0.2", "method": "POST", "path": "/upload?dir=../", "status": 200, "user_agent": "normal agent", "headers": {"X-Payload-Hash": "c0d1c238b6d3bc01b009e51c86dc43dd5cb8e3d8f10fb62453e9a56c4d7e63b6", "Host": "example.com"}}
{"ip": "10.0.0.3", "method": "GET", "path": "/upload?dir=../../", "status": 200, "user_agent": "Mozilla/5.0 <SCRIPT>alert(2)</SCRIPT>", "headers": {"X-Payload-Hash": "18a66fbc6100c5c41da367ea82b4da677ff8f44ffc91b5c468e21151664d4cbb", "Host": "example.com"}}
{"ip": "10.0.0.4", "method": "POST", "path": "/upload?dir=%2e%2e/etc", "status": 200, "user_agent": "test <script>evil</script>", "headers": {"X-Payload-Hash": "a61678229f6cd9dc5635f6ea50dd3ab179bf18f6d8a264a74de5e7e59b2075f7", "Host": "example.com"}}
{"ip": "10.0.0.5", "method": "POST", "path": "/upload?dir=../../var", "status": 403, "user_agent": "<script>a</script>", "headers": {"X-Payload-Hash": "18a66fbc6100c5c41da367ea82b4da677ff8f44ffc91b5c468e21151664d4cbb", "Host": "example.com"}}
{"ip": "10.0.0.6", "method": "POST", "path": "/upload?dir=../../opt", "status": 200, "user_agent": "some <script> payload", "headers": {"X-Payload-Hash": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "Host": "example.com"}}
EOF

    chmod -R 777 /home/user
