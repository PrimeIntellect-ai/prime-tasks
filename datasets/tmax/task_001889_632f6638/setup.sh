#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 time coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

bash -c '
mkdir -p /home/user/raw_data
for i in {1..50}; do
  words=$(( (RANDOM % 50) + 10 ))
  tr -dc "a-zA-Z0-9 " < /dev/urandom | head -c $words > /home/user/raw_data/doc_${i}.txt
  echo "" >> /home/user/raw_data/doc_${i}.txt
done
'

cat << 'EOF' > /usr/local/bin/mock_embed
#!/bin/bash
sleep 0.05
# Fake deterministic embedding based on file length and name
len=$(wc -c < "$1")
echo "[$len, 0.5, -0.1]"
EOF
chmod +x /usr/local/bin/mock_embed

chmod -R 777 /home/user
