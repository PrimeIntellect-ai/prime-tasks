#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'Target Reference: 10.0, 20.0, 30.0, 40.0, 50.0'" \
        -draw "text 10,70 'Max Euclidean Distance: 15.5'" \
        -draw "text 10,110 'Reject Token: FATAL_ERR_99'" \
        /app/config.png

    cat << 'EOF' > /app/corpus/clean/1.csv
timestamp,value,notes
1,12.0,ok
2,18.0,"normal
operation"
3,32.0,fine
4,41.0,good
5,49.0,nice
EOF

    cat << 'EOF' > /app/corpus/evil/1.csv
timestamp,value,notes
1,100.0,ok
2,20.0,ok
3,30.0,ok
4,40.0,ok
5,50.0,ok
EOF

    cat << 'EOF' > /app/corpus/evil/2.csv
timestamp,value,notes
1,10.0,ok
2,20.0,"error log:
FATAL_ERR_99 occurred"
3,30.0,ok
4,40.0,ok
5,50.0,ok
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
