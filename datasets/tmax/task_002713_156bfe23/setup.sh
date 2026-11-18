#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest PyJWT

mkdir -p /app/corpus/clean /app/corpus/evil /home/user

# Create the image fixture
convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
  -draw "text 20,50 'SECURITY POLICY v2.4'" \
  -draw "text 20,90 'HTTP Header: X-Corp-Sec-Auth'" \
  -draw "text 20,130 'JWT Secret Key: zulu-delta-niner-42'" \
  /app/policy_spec.png

# Generate Corpora
cat << 'EOF' > /tmp/gen_corpus.py
import json, jwt, os

SECRET = "zulu-delta-niner-42"
HEADER = "X-Corp-Sec-Auth"

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

def write_req(path, filename, data):
    with open(os.path.join(path, filename), 'w') as f:
        json.dump(data, f)

# Clean 1
valid_token = jwt.encode({"role": "uploader"}, SECRET, algorithm="HS256")
write_req('/app/corpus/clean', 'clean1.json', {
    "headers": {HEADER: f"Bearer {valid_token}"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/uploads/documents/"
})

# Clean 2
valid_token2 = jwt.encode({"role": "uploader", "user": "alice"}, SECRET, algorithm="HS256")
write_req('/app/corpus/clean', 'clean2.json', {
    "headers": {HEADER: f"Bearer {valid_token2}"},
    "upload_filename": "safe_image.png",
    "upload_path": "/var/data/uploads/images/"
})

# Evil 1: Bad signature
bad_sig_token = jwt.encode({"role": "uploader"}, "wrong-secret", algorithm="HS256")
write_req('/app/corpus/evil', 'evil1.json', {
    "headers": {HEADER: f"Bearer {bad_sig_token}"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/uploads/documents/"
})

# Evil 2: Wrong role
wrong_role_token = jwt.encode({"role": "guest"}, SECRET, algorithm="HS256")
write_req('/app/corpus/evil', 'evil2.json', {
    "headers": {HEADER: f"Bearer {wrong_role_token}"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/uploads/documents/"
})

# Evil 3: Path Traversal
write_req('/app/corpus/evil', 'evil3.json', {
    "headers": {HEADER: f"Bearer {valid_token}"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/uploads/../../../etc/"
})

# Evil 4: Encoded Path Traversal
write_req('/app/corpus/evil', 'evil4.json', {
    "headers": {HEADER: f"Bearer {valid_token}"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/%2E%2e%2Fuploads/"
})

# Evil 5: XSS in filename
write_req('/app/corpus/evil', 'evil5.json', {
    "headers": {HEADER: f"Bearer {valid_token}"},
    "upload_filename": "\"><script>alert(1)</script>.pdf",
    "upload_path": "/var/data/uploads/documents/"
})

# Evil 6: XSS onload in filename
write_req('/app/corpus/evil', 'evil6.json', {
    "headers": {HEADER: f"Bearer {valid_token}"},
    "upload_filename": "image.jpg\" ONLOAD=\"fetch('/steal')",
    "upload_path": "/var/data/uploads/documents/"
})

# Evil 7: Missing Header completely
write_req('/app/corpus/evil', 'evil7.json', {
    "headers": {"User-Agent": "curl/7.68.0"},
    "upload_filename": "report.pdf",
    "upload_path": "/var/data/uploads/documents/"
})

EOF
python3 /tmp/gen_corpus.py

useradd -m -s /bin/bash user || true
chown -R user:user /app/corpus /app/policy_spec.png /home/user
chmod -R 777 /home/user
