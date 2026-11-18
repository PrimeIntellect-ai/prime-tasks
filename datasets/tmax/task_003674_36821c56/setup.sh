#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        wget \
        curl \
        g++ \
        make

    pip3 install pytest

    # Create directories
    mkdir -p /app/include
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Download headers
    wget -q https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /app/include/httplib.h
    wget -q https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp -O /app/include/json.hpp

    # Create image with text
    # Note: escaping the backslash and quotes in the draw command
    convert -size 1200x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,50 'SYSTEM_RULE: DENY IF $.user.input MATCHES \"(?i)<script>|eval\(\"'" \
        /app/waf_schematic.png

    # Create corpus files
    for i in $(seq 1 10); do
        echo "{\"user\": {\"input\": \"Hello world $i\"}}" > /app/corpus/clean/clean_$i.json
    done

    for i in $(seq 1 5); do
        echo "{\"user\": {\"input\": \"<ScRiPt>alert($i)</script>\"}}" > /app/corpus/evil/evil_script_$i.json
        echo "{\"user\": {\"input\": \"eval(b64_$i)\"}}" > /app/corpus/evil/evil_eval_$i.json
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
