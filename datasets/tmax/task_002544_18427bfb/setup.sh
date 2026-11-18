#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu
    pip3 install pytest pandas flask fastapi uvicorn pytesseract

    mkdir -p /app
    cat << 'EOF' > /app/dataset.csv
id,featureA,featureB,split
1,1.5,2.1,train
2,2.3,3.0,train
3,3.1,4.2,train
4,4.5,5.1,train
5,5.2,5.9,train
6,10.0,-5.0,test
7,15.0,-10.0,test
8,20.0,-15.0,test
EOF

    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,60 'ETL_SECURE_TOKEN_99X'" /app/auth_token.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
