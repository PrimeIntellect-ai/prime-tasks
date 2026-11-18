#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install specific dependencies
    apt-get install -y tesseract-ocr imagemagick gcc build-essential fonts-dejavu-core gawk

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate the image fixture
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +20+50 "TARGET_COL: 2" \
        -annotate +20+90 "BOOTSTRAP_B: 2000" \
        -annotate +20+130 "THRESHOLD: 2.50" \
        /app/config.png

    # Generate clean data (volatility < 2.50)
    for i in $(seq 1 20); do
        awk -v seed=$i 'BEGIN {
            srand(seed);
            val=0;
            for(r=1;r<=100;r++) {
                v1 = rand();
                val += (rand()-0.5)*1.5; 
                v3 = rand();
                printf "%.4f,%.4f,%.4f\n", v1, val, v3;
            }
        }' > /app/corpora/clean/data_${i}.csv
    done

    # Generate evil data (volatility > 2.50)
    for i in $(seq 1 20); do
        awk -v seed=$i 'BEGIN {
            srand(seed+100);
            val=0;
            for(r=1;r<=100;r++) {
                v1 = rand();
                val += (rand()>0.5? 1 : -1) * (3.0 + rand());
                v3 = rand();
                printf "%.4f,%.4f,%.4f\n", v1, val, v3;
            }
        }' > /app/corpora/evil/data_${i}.csv
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
