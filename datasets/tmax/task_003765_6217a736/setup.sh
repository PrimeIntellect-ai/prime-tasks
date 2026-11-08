#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil
    pip3 install pytest

    mkdir -p /app

    # Generate the rules image using Python and Pillow
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
text = """Archive Processing Schema:
1. Security: If the original <filepath> contains the substring '..', output exactly "REJECTED: <original_filepath>" and ignore its content.
2. Sanitize paths: If accepted, replace every '/' and '\\' in the <filepath> with '_'.
3. Success: For accepted files, output "ACCEPTED: <sanitized_filepath>".
4. Data: Output all content lines of accepted files converted to uppercase.
5. End: Output "END ACCEPTED" after the content of an accepted file."""
img = Image.new('RGB', (1000, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/rules.png')
EOF
    python3 /tmp/make_image.py

    # Create oracle script
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
in_file=0
reject=0
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "BEGIN FILE: "* ]]; then
        in_file=1
        filepath="${line#BEGIN FILE: }"
        if [[ "$filepath" == *".."* ]]; then
            reject=1
            echo "REJECTED: $filepath"
        else
            reject=0
            sanitized="${filepath//\//_}"
            sanitized="${sanitized//\\/_}"
            echo "ACCEPTED: $sanitized"
        fi
    elif [[ "$line" == "END FILE" ]]; then
        if [ "$in_file" -eq 1 ] && [ "$reject" -eq 0 ]; then
            echo "END ACCEPTED"
        fi
        in_file=0
        reject=0
    else
        if [ "$in_file" -eq 1 ] && [ "$reject" -eq 0 ]; then
            echo "$line" | tr '[:lower:]' '[:upper:]'
        fi
    fi
done
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
