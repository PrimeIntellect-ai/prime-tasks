#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming_docs
mkdir -p /home/user/archive

cat << 'EOF' > /home/user/generator.sh
#!/bin/bash
mkdir -p /home/user/incoming_docs
for i in $(seq -w 1 50); do
    tmp_file="/home/user/incoming_docs/doc_${i}.tmp"
    md_file="/home/user/incoming_docs/doc_${i}.md"
    echo -e "# API Documentation ${i}\nStatus: INTERNAL_CONFIDENTIAL\nDetails: This is the payload for endpoint ${i}." > "$tmp_file"
    sleep 0.1
    mv "$tmp_file" "$md_file"
done
EOF

chmod +x /home/user/generator.sh

chmod -R 777 /home/user
