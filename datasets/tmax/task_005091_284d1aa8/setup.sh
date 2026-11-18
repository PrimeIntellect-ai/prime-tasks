#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gawk gsfonts
    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Generate experiment_notes.png using ImageMagick
    convert -background white -fill black -pointsize 18 label:"PIPELINE SPECS:\n1. Missing values: If feature_alpha or feature_beta is empty, treat it as 0.\n2. Model Architecture: score = 5 * feature_alpha - 3 * feature_beta + 10\n3. Outlier Criteria: If ANY row in the dataset produces a score > 100, the dataset is corrupted." /app/experiment_notes.png

    # Create clean files (scores <= 100)
    cat << 'EOF' > /app/clean/data1.csv
id,feature_alpha,feature_beta
1,10,20
2,,5
3,15,10
EOF
    cat << 'EOF' > /app/clean/data2.csv
id,feature_alpha,feature_beta
1,5,0
2,18,0
3,10,
EOF

    # Create evil files (at least one score > 100)
    cat << 'EOF' > /app/evil/data1.csv
id,feature_alpha,feature_beta
1,10,20
2,20,0
3,50,5
EOF
    cat << 'EOF' > /app/evil/data2.csv
id,feature_alpha,feature_beta
1,5,0
2,,
3,25,-5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
