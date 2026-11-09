#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate audio file
espeak -w /app/vendor_call.wav "Hello, this is cloud support. For your new deployment, please ensure the disk quota is set to exactly 512 megabytes. Furthermore, the supervisor must be configured with a restart policy of on-failure. Thank you."

# Create clean corpus
cat << 'EOF' > /app/corpus/clean/config1
Host *
  Port 22
  PubkeyAuthentication yes
EOF

cat << 'EOF' > /app/corpus/clean/config2
Host example
  User admin
EOF

# Create evil corpus
cat << 'EOF' > /app/corpus/evil/config1
Host *
  PubkeyAuthentication no
EOF

cat << 'EOF' > /app/corpus/evil/config2
Host *
  AuthorizedKeysFile /dev/null
EOF

cat << 'EOF' > /app/corpus/evil/config3
Host *
  PUBKEYAUTHENTICATION   NO
EOF

cat << 'EOF' > /app/corpus/evil/config4
Host *
  authorizedkeysfile /dev/null
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
