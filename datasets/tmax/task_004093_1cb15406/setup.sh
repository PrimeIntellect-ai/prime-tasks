#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gawk fonts-liberation
    pip3 install pytest

    mkdir -p /app/db /app/data/clean /app/data/evil

    cat << 'EOF' > /app/db/users.csv
1001,active,2021-01-01
1002,active,2021-02-01
1003,inactive,2021-03-01
1004,active,2021-04-01
EOF

    cat << 'EOF' > /app/data/clean/data1.csv
1001,3.2,0.8,0.6
EOF

    cat << 'EOF' > /app/data/clean/data2.csv
1004,2.55,0.707,0.707
EOF

    cat << 'EOF' > /app/data/evil/bad1.csv
1002.0,3.5,0.8,0.6
EOF

    cat << 'EOF' > /app/data/evil/bad2.csv
NaN,3.5,0.8,0.6
EOF

    cat << 'EOF' > /app/data/evil/bad3.csv
1003,4.0,1.0,0.0
EOF

    cat << 'EOF' > /app/data/evil/bad4.csv
1002,2.49,0.8,0.6
EOF

    cat << 'EOF' > /app/data/evil/bad5.csv
1001,3.0,0.4,0.4
EOF

    cat << 'EOF' > /app/data/evil/bad6.csv
1001,3.0,1.2,1.2
EOF

    # Fix ImageMagick policy to allow label generation if needed
    sed -i 's/rights="none" pattern="LABEL"/rights="read|write" pattern="LABEL"/g' /etc/ImageMagick-6/policy.xml || true

    convert -background white -fill black -font Liberation-Sans -pointsize 18 label:"Rules:\n1. user_id MUST be strictly integer, no decimals, no NaN.\n2. score MUST be greater than 2.50.\n3. Joined status from users.csv MUST be 'active'.\n4. The L2 norm of (vector_x, vector_y) MUST be strictly greater than 0.9 and less than 1.1." /app/schema_guide.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
