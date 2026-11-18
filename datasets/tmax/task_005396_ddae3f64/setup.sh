#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data
mkdir -p /home/user/reports
mkdir -p /home/user/logs

cat << 'EOF' > /home/user/data/feedback.csv
id|username|feedback_text
1|alice|The product is absolutely fantastic! I love the quality.
2|bob|Quality is terrible. The delivery was incredibly slow.
3|charlie|Fantastic quality! Will definitely order this product again.
4|diana|Delivery was slow, but the product quality makes up for it.
5|eve|Absolutely terrible customer service. Slow response.
6|frank|I love this product! Fantastic build quality.
EOF

# Use variables for braces to avoid Apptainer interpreting them as build variables
L="{"
R="}"
cat << EOF > /home/user/template.txt
Daily Feedback Report
Most frequent words:
1. ${L}${L}WORD1${R}${R} (${L}${L}COUNT1${R}${R})
2. ${L}${L}WORD2${R}${R} (${L}${L}COUNT2${R}${R})
3. ${L}${L}WORD3${R}${R} (${L}${L}COUNT3${R}${R})
EOF

chmod -R 777 /home/user
