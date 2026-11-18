#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick gawk tesseract-ocr
    pip3 install pytest pytesseract Pillow

    mkdir -p /app

    # Generate the system parameters image
    convert -size 400x300 xc:white -fill black -pointsize 24 \
    -draw "text 20,50 'Simulation Parameters:'" \
    -draw "text 20,90 'R = 3.82'" \
    -draw "text 20,130 'X0 = 0.5'" \
    -draw "text 20,170 'LCG_A = 1103515245'" \
    -draw "text 20,210 'LCG_C = 12345'" \
    -draw "text 20,250 'LCG_M = 2147483648'" \
    /app/system_params.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle
#!/bin/bash
N=$1
seed=$2

awk -v N="$N" -v seed="$seed" '
BEGIN {
    R = 3.82
    X = 0.5
    LCG_A = 1103515245
    LCG_C = 12345
    LCG_M = 2147483648
    S = seed

    for (i = 1; i <= N; i++) {
        S = (LCG_A * S + LCG_C) % LCG_M
        perturb = (S / LCG_M - 0.5) * 0.01
        X = R * X * (1 - X) + perturb
        printf "%.6f\n", X
    }
}'
EOF
    chmod +x /app/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
