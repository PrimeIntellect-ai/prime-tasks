#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow pandas

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Clean 1: Standard clean file
    cat << 'EOF' > /app/corpora/clean/clean1.csv
timestamp,user_id,LOGIN,LOGOUT,QUERY,EXPORT
2023-01-01T10:00:00Z,101,Success,,,
2023-01-01T10:05:00Z,101,,Success,,
2023-01-01T10:10:00Z,102,,,SELECT * FROM users,
EOF

    # Clean 2: Multiple events per row (valid wide format)
    cat << 'EOF' > /app/corpora/clean/clean2.csv
timestamp,user_id,LOGIN,LOGOUT,QUERY,EXPORT
2023-01-02T11:00:00Z,205,IP:192.168.1.1,,,Exported 50 rows
EOF

    # Evil 1: Embedded newline in details
    cat << 'EOF' > /app/corpora/evil/evil1.csv
timestamp,user_id,LOGIN,LOGOUT,QUERY,EXPORT
2023-01-01T10:00:00Z,101,"Success
Admin",,,
EOF

    # Evil 2: Duplicate records after reshaping
    cat << 'EOF' > /app/corpora/evil/evil2.csv
timestamp,user_id,LOGIN,LOGOUT,QUERY,EXPORT
2023-01-01T10:00:00Z,101,Success,,,
2023-01-01T10:00:00Z,101,Success,,,
EOF

    # Generate the policy image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color='white')
d = ImageDraw.Draw(img)
text = '''LOG VALIDATION POLICY
1. Input format: Wide CSV with columns (timestamp, user_id, LOGIN, LOGOUT, QUERY, EXPORT).
2. Reshape to long format: (timestamp, user_id, event_type, details) where event_type is the column name.
3. Drop rows where 'details' is empty or null.
4. REJECT FILE if any 'details' field contains embedded newlines (CR or LF characters).
5. REJECT FILE if there are duplicate records based on (timestamp, user_id, event_type) after reshaping.'''
d.text((20,40), text, fill='black')
img.save('/app/policy.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
