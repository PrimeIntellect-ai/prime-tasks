#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gcc binutils make
    pip3 install pytest

    mkdir -p /home/user/build /opt/sec_libs

    cat <<EOF > /home/user/deps.json
{
  "lib_name": "libwebsec",
  "min_version": "2.4.1",
  "symbol": "websec_verify_token"
}
EOF

    echo "2.1.9" > /opt/sec_libs/version.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
