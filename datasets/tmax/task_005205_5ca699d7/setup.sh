#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick g++ 
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the system specs image
    convert -size 400x200 xc:white -fill black -pointsize 24 -annotate +10+40 "SYSTEM CONFIGURATION\nSENSORS: temp,volt,rpm\nSALT: z9X_#Lq2" /app/system_specs.png

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/data1.csv
timestamp,temp,volt,rpm
1678886400,22.5,-1.2,3000
1678886401,22.6,-1.1,3010
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/data1.csv
timestamp,temp,volt,rpm
1678886402,22.5,1.2; DROP TABLE sensors,3000
1678886403,NaN,-1.2,3000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
