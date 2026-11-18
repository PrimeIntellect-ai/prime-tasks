#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect ffmpeg systemd
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/legacy_configurator
#!/bin/bash
read -p "Username: " user
read -p "Password: " pass
read -p "Dashboard ID: " dash
echo "{\"dashboard_id\": \"$dash\", \"username\": \"$user\", \"password\": \"$pass\"}" > /home/user/config.json
EOF
    chmod +x /app/legacy_configurator

    # Generate a video with exactly 12 red frames (1 second at 12 fps)
    ffmpeg -y -f lavfi -i color=c=red:s=100x100:d=1 -r 12 /app/dashboard_recording.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
