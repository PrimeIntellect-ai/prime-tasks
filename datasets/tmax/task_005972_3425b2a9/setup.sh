#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest Pillow PyYAML

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project/raw_assets
cd /home/user/project/raw_assets

# Create valid 1x1 pixel images (Base64)
# 1x1 PNG (Red)
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > "User-Avatar 01.PNG"
# 1x1 JPG (Blue)
echo "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=" | base64 -d > "Hero Banner.jpg"

# Create JSON files
cat << 'EOF' > "Server-Config.json"
{
  "host": "localhost",
  "port": 8080,
  "debug": true,
  "features": ["auth", "logging"]
}
EOF

cat << 'EOF' > "UI Settings.json"
{
  "theme": "dark",
  "animations": false
}
EOF

chown -R user:user /home/user/project
chmod -R 777 /home/user
