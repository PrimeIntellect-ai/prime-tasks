#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow numpy scipy

    mkdir -p /app

    cat << 'EOF' > /app/seq_stats.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    int gc = 0, total = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '>') {
            if (total > 0) {
                printf("%f\n", (float)gc / total);
                gc = 0; total = 0;
            }
        } else {
            for (int i = 0; line[i] != '\0'; i++) {
                if (line[i] == 'G' || line[i] == 'C') gc++;
                if (line[i] >= 'A' && line[i] <= 'Z') total++;
            }
        }
    }
    if (total > 0) printf("%f\n", (float)gc / total);
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /app/reads.fasta
>read1
ATGCGTAACGCGCGCGTG
>read2
CGCGCGCGCGCGCGCGCG
>read3
ATATATATATATATATAT
>read4
GCGCATGCATGCATGCAT
>read5
CCCGGGCCCGGGCCCGGG
EOF

    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (600, 100), color="white")
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
d.text((10, 40), "PRIOR_MU=0.45, PRIOR_SIGMA=0.08", fill="black", font=font)
img.save("/app/gel_band.png")
'

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
