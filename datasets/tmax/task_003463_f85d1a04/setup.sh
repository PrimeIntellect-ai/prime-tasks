#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        cron \
        fonts-dejavu-core

    pip3 install pytest pandas pytesseract Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create the config image
    convert -size 500x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'WINDOW=5 MAX_DEV=2.5 ENCODING=utf-8'" /app/config_label.png

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.csv
timestamp,temperature,notes
2023-01-01T00:00:00Z,10.0,ok
2023-01-01T00:01:00Z,10.1,all good
2023-01-01T00:02:00Z,10.2,fine
2023-01-01T00:03:00Z,10.1,ok
2023-01-01T00:04:00Z,10.0,ok
EOF
    cp /app/corpora/clean/clean1.csv /app/corpora/clean/clean2.csv
    cp /app/corpora/clean/clean1.csv /app/corpora/clean/clean3.csv
    cp /app/corpora/clean/clean1.csv /app/corpora/clean/clean4.csv
    cp /app/corpora/clean/clean1.csv /app/corpora/clean/clean5.csv

    # Create evil corpus
    # 1. Script injection
    cat << 'EOF' > /app/corpora/evil/evil1_script.csv
timestamp,temperature,notes
2023-01-01T00:00:00Z,10.0,<script>alert(1)</script>
2023-01-01T00:01:00Z,10.0,ok
EOF

    # 2. Temperature spike (deviation > 2.5)
    cat << 'EOF' > /app/corpora/evil/evil2_spike.csv
timestamp,temperature,notes
2023-01-01T00:00:00Z,10.0,ok
2023-01-01T00:01:00Z,10.0,ok
2023-01-01T00:02:00Z,10.0,ok
2023-01-01T00:03:00Z,10.0,ok
2023-01-01T00:04:00Z,10.0,ok
2023-01-01T00:05:00Z,15.0,spike
EOF

    # 3. UTF-16 Encoding
    python3 -c "open('/app/corpora/evil/evil3_encoding.csv', 'w', encoding='utf-16').write('timestamp,temperature,notes\n2023-01-01T00:00:00Z,10.0,ok\n')"

    cp /app/corpora/evil/evil1_script.csv /app/corpora/evil/evil4.csv
    cp /app/corpora/evil/evil2_spike.csv /app/corpora/evil/evil5.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
