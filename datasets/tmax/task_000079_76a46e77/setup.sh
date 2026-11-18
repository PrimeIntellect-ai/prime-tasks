#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /home/user/src /home/user/bin /app/corpora/spectra/evil /app/corpora/spectra/clean

cat << 'EOF' > /home/user/src/estimator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4 || strcmp(argv[1], "--tol") != 0) {
        return 1;
    }
    // Mock logic: return a high condition number for "evil" files, low for "clean"
    if (strstr(argv[3], "evil") != NULL) {
        printf("850.5\n"); // > 500.0
    } else {
        printf("120.2\n"); // < 500.0
    }
    return 0;
}
EOF

for i in $(seq 1 5); do
    touch "/app/corpora/spectra/evil/spec_$i.spec"
    touch "/app/corpora/spectra/clean/spec_$i.spec"
done

convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 16 -fill black -draw "text 10,50 'CALIBRATION_DATA: MAX_CONDITION_NUM=500.0 ; CONV_TOL=1e-6'" /app/calibration.png

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
chmod -R 777 /app
