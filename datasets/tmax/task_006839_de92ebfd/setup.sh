#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

# Create initial dashboard config
cat << 'EOF' > /home/user/dashboard.json
{
  "users": [
    {
      "username": "guest",
      "group": "guests"
    }
  ],
  "monitored_targets": [
    "127.0.0.1:9090"
  ]
}
EOF

# Create a bash wrapper to start the dummy listener when a shell is spawned
mv /bin/bash /bin/bash.orig
cat << 'EOF' > /bin/bash
#!/bin/bash.orig
# Start a dummy listener on 8001 if it's not already running
python3 -m http.server 8001 --bind 127.0.0.1 >/dev/null 2>&1 &
exec /bin/bash.orig "$@"
EOF
chmod +x /bin/bash

chmod -R 777 /home/user
