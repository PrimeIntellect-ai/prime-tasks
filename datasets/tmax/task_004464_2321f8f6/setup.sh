#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        git \
        imagemagick \
        gawk \
        fonts-liberation

    pip3 install pytest opencv-python-headless scikit-image

    mkdir -p /app
    # Create the dev_notes.png using ImageMagick
    convert -size 500x150 xc:white -fill black -pointsize 20 \
        -draw "text 20,50 'SCALE_FACTOR = (WIDTH * 0.65) + 22.5'" \
        -draw "text 20,100 'ENCODING_TARGET: UTF-8'" \
        /app/dev_notes.png

    # Create user
    useradd -m -s /bin/bash user || true

    # Create input data
    echo "WIDTH=100" > /home/user/input_data.dat

    # Set up git repository
    mkdir -p /home/user/data_pipeline
    cd /home/user/data_pipeline
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1
    cat << 'EOF' > process.sh
#!/bin/bash
INPUT=$1
cp $INPUT temp.cfg
iconv -f UTF-8 -t UTF-8 temp.cfg > temp_enc.cfg
SCALE=$(awk -F= '/WIDTH/ { print int(($2 * 0.5) + 10) }' temp_enc.cfg)
convert -size 100x${SCALE} xc:black /home/user/final_output.png
EOF
    chmod +x process.sh
    git add process.sh
    git commit -m "Initial commit"

    # Commits 2 and 3
    echo "# minor update 1" >> process.sh; git commit -am "Commit 2"
    echo "# minor update 2" >> process.sh; git commit -am "Commit 3"

    # Commit 4 (Introduce encoding bug)
    sed -i 's/iconv -f UTF-8 -t UTF-8/iconv -f UTF-8 -t UTF-16LE/' process.sh
    git commit -am "Commit 4: optimize encoding format"

    # Commits 5 to 8
    for i in {5..8}; do echo "# minor update $i" >> process.sh; git commit -am "Commit $i"; done

    # Commit 9 (Introduce formula bug)
    sed -i 's/\$2 \* 0.5/\$2 \* 0.9/' process.sh
    sed -i 's/+ 10/- 5/' process.sh
    git commit -am "Commit 9: update formula parameters"

    # Generate reference truth image
    # The correct formula is (WIDTH * 0.65) + 22.5
    # WIDTH = 100 -> SCALE = int((100 * 0.65) + 22.5) = int(65 + 22.5) = int(87.5) = 87
    convert -size 100x87 xc:black /tmp/reference_truth.png

    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod 777 /tmp/reference_truth.png
