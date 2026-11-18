#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect tesseract-ocr fonts-liberation
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    cat << 'EOF' > /app/secure_quota_check.sh
#!/bin/bash
echo -n "Enter monitoring password: "
read -s password
echo
if [ "$password" == "mon_alert_99" ]; then
    echo "DISK_USAGE=8492"
else
    echo "Authentication failed."
    exit 1
fi
EOF
    chmod +x /app/secure_quota_check.sh

    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (600, 200), color="white")
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
except:
    font = ImageFont.load_default()
d.text((10,10), "ALERT DAEMON CONFIGURATION\nPORT=8192\nTOKEN=AlphaTango!44", fill=(0,0,0), font=font)
img.save("/app/alert_config.png")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
