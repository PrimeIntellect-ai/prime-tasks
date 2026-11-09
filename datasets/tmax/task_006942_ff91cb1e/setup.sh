#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_docs.csv
file_path,chunk_index,content_base64
../../../../../home/user/malicious.txt,1,d29ybGQh
../../../../../home/user/malicious.txt,0,SGVsbG8g
guides/setup.md,0,IyBTZXR1cAoK
guides/setup.md,1,UnVuIHRoZSBzY3JpcHQu
../api_ref.csv,2,MixCb2IK
../api_ref.csv,0,SUQsTkFNRQo=
../api_ref.csv,1,MSxBbGljZQo=
EOF

    chmod -R 777 /home/user
