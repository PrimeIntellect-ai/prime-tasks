#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
pip3 install pytest

mkdir -p /app /home/user

# Create the screenshot image using ImageMagick
# We use a white background and black text with a clear font to ensure tesseract can read it easily.
convert -size 1200x150 xc:white -fill black -font Liberation-Sans -pointsize 24 -annotate +20+60 "Exploit successful. Persistent backdoor listening on port 31337. Exfiltration server ready at 10.9.8.7." /app/screenshot.png

# Create netstat log
cat << 'EOF' > /home/user/netstat.log
Proto Recv-Q Send-Q Local Address           Foreign Address         State
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN
tcp        0      0 192.168.1.10:22         203.0.113.5:54321       ESTABLISHED
tcp        0      0 0.0.0.0:31337           0.0.0.0:*               LISTEN
tcp        0      0 192.168.1.10:31337      198.51.100.42:49152     ESTABLISHED
tcp        0      0 127.0.0.1:3306          0.0.0.0:*               LISTEN
EOF

# Create compromised sshd_config
cat << 'EOF' > /home/user/sshd_config_compromised
Port 22
Protocol 1
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding yes
AllowTcpForwarding yes
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
