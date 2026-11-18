#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the policy image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''SECURITY POLICY: If a manifest has 'kind' equal to 'Secret' and
'metadata.annotations.ssh-auth' is set to 'true', you must completely
remove the 'data.authorized_keys' field. All other fields must remain untouched.'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/operator_policy.png')
"

    # Create the reference filter
    cat << 'EOF' > /app/reference_filter
#!/usr/bin/env python3
import sys
import json

def process(data):
    if not isinstance(data, dict):
        return data
    if data.get("kind") == "Secret":
        metadata = data.get("metadata", {})
        if isinstance(metadata, dict):
            annotations = metadata.get("annotations", {})
            if isinstance(annotations, dict) and annotations.get("ssh-auth") == "true":
                data_field = data.get("data")
                if isinstance(data_field, dict) and "authorized_keys" in data_field:
                    del data_field["authorized_keys"]
    return data

def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            return
    except Exception:
        return

    try:
        parsed = json.loads(input_data)
        result = process(parsed)
        print(json.dumps(result))
    except Exception:
        print(input_data, end="")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/reference_filter

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
