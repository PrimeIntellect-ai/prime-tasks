#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr fonts-liberation
pip3 install pytest Pillow pytesseract flask fastapi uvicorn requests

mkdir -p /app
cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 40)
d.text((20,20), "15 5 + 4 *", fill=(0,0,0), font=font)
img.save('/app/equation.png')
EOF
python3 /tmp/gen_image.py
rm /tmp/gen_image.py

useradd -m -s /bin/bash user || true
mkdir -p /home/user

cat << 'EOF' > /home/user/evaluator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int evaluate_rpn(const char* expr) {
    int stack[10]; // Bug: Stack overflow for large expressions
    int top = -1;
    char buffer[256]; // Bug: Buffer overflow for long strings
    strcpy(buffer, expr); 

    char *token = strtok(buffer, " ");
    while (token != NULL) {
        if (token[0] >= '0' && token[0] <= '9') {
            stack[++top] = atoi(token);
        } else if (token[0] == '+') {
            int b = stack[top--];
            int a = stack[top--];
            stack[++top] = a + b;
        } else if (token[0] == '*') {
            int b = stack[top--];
            int a = stack[top--];
            stack[++top] = a * b;
        }
        token = strtok(NULL, " ");
    }
    return stack[top];
}
EOF

chmod -R 777 /home/user
chmod -R 777 /app
