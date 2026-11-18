#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Download a font and generate the memo image using Python
    wget -q https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Regular.ttf -O /tmp/Roboto.ttf
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/tmp/Roboto.ttf", 24)
text = "URGENT MANDATE. All streaming logs must be filtered. You must REJECT any line containing the exact token 'FORBIDDEN_KEY_77X'. You must also REJECT any line where the case-insensitive word 'critical_failure' appears. Collapse consecutive identical lines."
d.text((10, 50), text, fill=(0, 0, 0), font=font)
img.save('/app/memo.png')
EOF
    python3 /tmp/gen_img.py
    rm /tmp/gen_img.py /tmp/Roboto.ttf

    # Create corpora directories and files
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /app/corpora/evil/evil1.log
This line has the FORBIDDEN_KEY_77X token in it.
Here is a CRITICAL_FAILURE that must be rejected.
Another line with critical_failure.
FORBIDDEN_KEY_77X at the start.
End of the line with FORBIDDEN_KEY_77X
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.log
critical_failure is everywhere.
What about CrItIcAl_FaIlUrE?
FORBIDDEN_KEY_77X
EOF

    cat << 'EOF' > /app/corpora/clean/clean1.log
This is a perfectly fine log line.
Another normal log line.
A third normal line.
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.log
System started successfully.
All services running.
No issues detected.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
