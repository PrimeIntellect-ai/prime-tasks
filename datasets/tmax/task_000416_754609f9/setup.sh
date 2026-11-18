#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cmake build-essential valgrind
    pip3 install pytest Pillow

    mkdir -p /app/src
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'URGENT RELEASE NOTES:\nTarget architecture: x86_64\nEnforce strict bounds.\nMAX_AST_DEPTH=35\nEnsure no memory leaks.'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/release_spec.png')
"

    # Create src files
    cat << 'EOF' > /app/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
    return 0;
}
EOF

    cat << 'EOF' > /app/src/parser.cpp
struct Node {
    Node* left;
    Node* right;
};

Node* parse() {
    return new Node();
}
EOF

    # Create corpora
    echo "(5 + 3) * 2 / 4" > /app/corpus/clean/test1.ms
    echo "1 / (5 - 5)" > /app/corpus/evil/evil1.ms
    echo "((((((((((((((((((((((((((((((((((((((((1))))))))))))))))))))))))))))))))))))))))" > /app/corpus/evil/evil2.ms

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
