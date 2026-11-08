#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tesseract-ocr imagemagick
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /home/user/ingest-repo

    # Generate image
    convert -size 800x200 xc:black -font DejaVu-Sans -pointsize 18 -fill white \
        -draw "text 10,50 'Serialization Panic: Unescaped BOM at offset 0. Build failed. Revert to commit a7b8c9d.'" \
        /app/alert_trace.png

    # Setup git repo
    cd /home/user/ingest-repo
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"

    echo "echo 'init'" > build.sh
    git add build.sh
    git commit -m "Initial commit"

    echo "#!/bin/bash" > validate.sh
    echo "grep -q $'\\xEF\\xBB\\xBF' \$1 && exit 1" >> validate.sh
    echo "X-API-Key: 99x-auth-secret-val" > secret.txt
    git add validate.sh secret.txt
    git commit -m "Add validation and secret (commit a7b8c9d)"

    rm validate.sh secret.txt
    git rm validate.sh secret.txt
    git commit -m "Remove validation and secret"

    # Setup Evil Corpus
    printf '\xEF\xBB\xBF{"status": "ok"}' > /app/corpus/evil/payload1.json
    echo "99x-auth-secret-val" | base64 > /app/corpus/evil/payload2.txt
    printf '\xEF\xBB\xBF{"key": "99x-auth-secret-val"}' > /app/corpus/evil/payload3.json

    # Setup Clean Corpus
    echo '{"status": "ok"}' > /app/corpus/clean/config1.json
    echo "Just some normal text." > /app/corpus/clean/config2.txt
    echo '{"word": "secret"}' > /app/corpus/clean/config3.json

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
