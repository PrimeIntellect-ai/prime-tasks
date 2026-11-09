#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core gcc bc gawk
    pip3 install pytest

    mkdir -p /app/src /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/src/calc_det.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    double m[3][3];
    for (int i=0; i<3; i++) {
        for (int j=0; j<3; j++) {
            if (fscanf(f, "%lf", &m[i][j]) != 1) return 1;
        }
    }
    fclose(f);
    double det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                 m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                 m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    printf("%.6f\n", det);
    return 0;
}
EOF

    # Generate image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 20,50 'Note for simulation: The molecular adjacency'" \
        -draw "text 20,80 'determinant threshold is 0.005. Anything below'" \
        -draw "text 20,110 'this absolute value will cause convergence failure.'" \
        /app/lab_notes_scan.png

    # Generate corpora
    for i in $(seq 1 50); do
        echo "1.0 0.2 0.1" > /app/corpus/clean/m$i.txt
        echo "0.2 1.0 0.2" >> /app/corpus/clean/m$i.txt
        echo "0.1 0.2 1.0" >> /app/corpus/clean/m$i.txt
    done

    for i in $(seq 1 50); do
        echo "1.0 1.0 1.0" > /app/corpus/evil/m$i.txt
        echo "1.0 1.0 1.0" >> /app/corpus/evil/m$i.txt
        echo "1.0 1.0 1.0" >> /app/corpus/evil/m$i.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
