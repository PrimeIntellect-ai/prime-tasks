#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu gawk coreutils
    pip3 install pytest

    mkdir -p /app/eval_corpus/clean /app/eval_corpus/evil

    # 1. Generate the image fixture
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Master Salt: Omega99X'" /app/arch_notes.png

    # 2. Generate the Clean Corpus (Valid tokens)
    echo -n "Omega99Xbob1234" | sha256sum | awk '{print "bob:"$1}' > /app/eval_corpus/clean/log_01.txt
    echo -n "Omega99Xadmin0042" | sha256sum | awk '{print "admin:"$1}' > /app/eval_corpus/clean/log_02.txt
    echo -n "Omega99Xcharlie9999" | sha256sum | awk '{print "charlie:"$1}' > /app/eval_corpus/clean/log_03.txt

    # 3. Generate the Evil Corpus (Forged tokens)
    echo -n "randomjunk1" | sha256sum | awk '{print "bob:"$1}' > /app/eval_corpus/evil/log_01.txt
    echo -n "randomjunk2" | sha256sum | awk '{print "admin:"$1}' > /app/eval_corpus/evil/log_02.txt
    echo -n "randomjunk3" | sha256sum | awk '{print "charlie:"$1}' > /app/eval_corpus/evil/log_03.txt

    chmod -R 755 /app/eval_corpus
    chmod 644 /app/arch_notes.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
