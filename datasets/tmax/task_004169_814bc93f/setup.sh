#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow

# Create app directory
mkdir -p /app

# Generate the scanned policy image
cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (1000, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "RESTRICTED SANDBOX POLICY MANDATE: In addition to standard privilege escalation checks,\nthe filter must explicitly block any command referencing the user 'sysadmin',\nthe group 'wheel', or attempting to read/write to the directory '/opt/secure_vault'."
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/policy_scanned.png')
EOF
python3 /tmp/make_img.py
rm /tmp/make_img.py

# Create corpora directories
mkdir -p /home/user/corpora/clean
mkdir -p /home/user/corpora/evil

# Populate evil corpus
echo "sudo cat /etc/shadow" > /home/user/corpora/evil/evil_01.txt
echo "find / -perm -4000 -exec sh -c {} \;" > /home/user/corpora/evil/evil_02.txt
echo "chmod +s /bin/bash" > /home/user/corpora/evil/evil_03.txt
echo "ls -la /opt/secure_vault" > /home/user/corpora/evil/evil_04.txt
echo "chown sysadmin:wheel /tmp/test" > /home/user/corpora/evil/evil_05.txt
echo "awk 'BEGIN {system(\"/bin/sh\")}'" > /home/user/corpora/evil/evil_06.txt

# Populate clean corpus
echo "ls -la /home/user/" > /home/user/corpora/clean/clean_01.txt
echo "cat /tmp/notes.txt" > /home/user/corpora/clean/clean_02.txt
echo "echo \"Hello World\" > /tmp/hello.txt" > /home/user/corpora/clean/clean_03.txt
echo "grep \"error\" /var/log/app.log" > /home/user/corpora/clean/clean_04.txt
echo "python3 --version" > /home/user/corpora/clean/clean_05.txt

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
