#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pycryptodome

    mkdir -p /home/user

    cat << 'EOF' > /home/user/app_config.json
{
  "AES_KEY": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "AES_IV": "abcdef9876543210abcdef9876543210"
}
EOF

    cat << 'EOF' > /home/user/intercepted_request.txt
GET /login?state=db6b26ea8bd4c54ed3dd3fa44af64e2978dff2a7587747e9e8f081498b8cba8c HTTP/1.1
Host: legacy.local
User-Agent: Mozilla/5.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
