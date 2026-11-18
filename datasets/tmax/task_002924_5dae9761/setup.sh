#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu tesseract-ocr
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create image fixture
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'BUILD_TOKEN=Vortex99'" /app/build_architecture.png

    # Generate Clean Corpus
    cat << 'EOF' > /app/corpus/clean/clean1.txt
build://compile_c?token=Vortex99&target=main_app&flags=-O2 -Wall
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.txt
build://compile_py?token=Vortex99&target=script1&flags=--optimize
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.txt
build://link_bin?token=Vortex99&target=final_bin&flags=-static
EOF

    # Generate Evil Corpus (Adversarial)
    cat << 'EOF' > /app/corpus/evil/evil1.txt
build://compile_c?token=Vortex99&target=../../../etc/passwd&flags=-O2
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.txt
build://compile_py?token=Vortex99&target=app&flags=--optimize;rm -rf /
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.txt
build://delete_all?token=Vortex99&target=app&flags=-O2
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.txt
build://compile_c?token=Admin123&target=app&flags=-O2
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.txt
build://link_bin?token=Vortex99&target=app&flags=-O2 $PATH
EOF

    chmod -R 755 /app/corpus

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
