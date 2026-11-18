#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr socat expect curl imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_admin_cli
#!/bin/bash
read -p "Username: " user
read -s -p "Password: " pass
echo
if [ "$user" == "admin" ] && [ "$pass" == "legacy2024" ]; then
    echo "app1:192.168.1.10"
    echo "app2:192.168.1.11"
    echo "db_main:10.0.0.5"
else
    echo "Authentication failed."
    exit 1
fi
EOF
    chmod +x /app/legacy_admin_cli

    # Create the config snapshot image
    convert -background white -fill black -font Liberation-Mono -pointsize 24 label:"APPLIANCE NETWORK SETTINGS\nBIND_PORT=8443\nAUTH_TOKEN=super-secret-77X" /app/config_snapshot.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
