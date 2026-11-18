#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends python3 python3-pip expect ffmpeg
pip3 install pytest

mkdir -p /app
# Generate a short sample video
ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -c:v libx264 -pix_fmt yuv420p /app/traffic_cam.mp4

# Create mock legacy_vault
cat << 'EOF' > /app/legacy_vault
#!/bin/bash
read -p "Username: " user
read -p "Migration Pin: " pin
read -p "Action: " action
if [ "$user" == "cloud_admin" ] && [ "$pin" == "8821" ] && [ "$action" == "GET_TOKEN" ]; then
    echo "TOKEN_99AABBCC"
else
    echo "AUTH_FAILED"
fi
EOF
chmod +x /app/legacy_vault

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
