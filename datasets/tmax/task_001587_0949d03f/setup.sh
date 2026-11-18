#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /home/user/rust_project
    mkdir -p /app

    # Generate the image with the formula
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,100 'Formula: Complexity Score = (Lifetimes * Lifetimes + Variables * Functions) % 10007'" /app/formula_spec.png

    # Generate 10,000 mock Rust files
    python3 -c '
import random
import os

os.makedirs("/home/user/rust_project", exist_ok=True)
random.seed(42)

for i in range(10000):
    l = random.randint(1, 100)
    v = random.randint(10, 500)
    f = random.randint(1, 50)
    content = "// Metadata:\n// Lifetimes: " + str(l) + "\n// Variables: " + str(v) + "\n// Functions: " + str(f) + "\n\nfn main() {}\n"
    filename = "/home/user/rust_project/file_" + str(i).zfill(4) + ".rs"
    with open(filename, "w") as f_out:
        f_out.write(content)
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/rust_project /app/formula_spec.png || true
    chmod -R 777 /home/user
