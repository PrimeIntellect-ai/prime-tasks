#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the storage policy image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """STORAGE MANAGEMENT POLICY V2.1
All archived logs must follow these constraints:
1. Output encoding MUST be UTF-8. Convert from ISO-8859-1 if necessary.
2. Bulk rename all target processed files to have the prefix 'archived_clean_'.
3. DROP all multi-line log records where the severity level is [TRACE].
4. Preserve all [INFO], [WARN], and [ERROR] records."""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/storage_policy.png')
EOF
    python3 /tmp/make_image.py

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/log_filter_oracle.py
#!/usr/bin/env python3
import sys
import re

def main():
    raw_data = sys.stdin.buffer.read()
    try:
        text = raw_data.decode('utf-8')
    except UnicodeDecodeError:
        text = raw_data.decode('iso-8859-1')

    records = []
    current_record = []
    for line in text.splitlines(keepends=True):
        if re.match(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]', line):
            if current_record:
                records.append("".join(current_record))
                current_record = []
        current_record.append(line)
    if current_record:
        records.append("".join(current_record))

    for record in records:
        # Check if the header contains [TRACE]
        header = record.split('\n')[0] if record else ""
        if "[TRACE]" not in header:
            sys.stdout.buffer.write(record.encode('utf-8'))

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/log_filter_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
