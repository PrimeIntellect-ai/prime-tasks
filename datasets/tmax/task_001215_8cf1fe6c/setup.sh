#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr tar xz-utils
    pip3 install pytest Pillow

    mkdir -p /app/repo/nested

    # Create files for repo
    echo "dummy" > /app/repo/legacy-v1-file1.txt
    echo "dummy" > /app/repo/beta-v2-file2.txt
    echo "dummy" > /app/repo/some-other-file.bdat
    echo "dummy" > "/app/repo/nested/legacy-v1-file 3.bdat"

    cat << 'EOF' > /app/repo/nested/beta-v2-file4.manifest
Header 1
Header 2
Header 3
Header 4
Header 5
Content with legacy-v1- prefix
Content with beta-v2- prefix
EOF

    cat << 'EOF' > /app/repo/nested/normal.manifest
Header 1
Header 2
Header 3
Header 4
Header 5
Content with legacy-v1- prefix
Content with beta-v2- prefix
EOF

    cd /app && tar -cf repo.tar repo
    rm -rf /app/repo

    # Generate curation_rules.png
    python3 -c "
from PIL import Image, ImageDraw
text = '''ARTIFACT CURATION POLICY V2.1
-----------------------------
PREFIX_RENAME: legacy-v1- -> archived-alpha-
PREFIX_RENAME: beta-v2- -> stable-v2-
ARCHIVE_SUFFIX: .bdat
MANIFEST_ACTION: STRIP_HEADER_LINES=5'''
img = Image.new('RGB', (600, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/curation_rules.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
