#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        netcat-openbsd \
        socat \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/test-util

    # Create setup.py with a syntax error
    cat << 'EOF' > /app/test-util/setup.py
from setuptools import setup

setup(
    name='test-util',
    version='0.1.0',
    description='A mock server testing utility',
    install_requires=['requests'
)
EOF

    # Create server.sh skeleton
    cat << 'EOF' > /app/test-util/server.sh
#!/bin/bash
# TODO: Implement the mock server
EOF
    chmod +x /app/test-util/server.sh

    # Generate the configuration image
    # Temporarily modify ImageMagick policy to allow writing if needed, though usually not required for PNG
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"TEST CONFIGURATION\nPORT: 9055\nTOKEN: GO_MOCK_XYZ123" /app/server_config.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
