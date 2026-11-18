#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc sqlite3 fonts-dejavu
pip3 install pytest

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

cat << 'EOF' > /app/corpora/clean/clean1.csv
source_id,target_id,weight,timestamp
10,20,50,1600000000
10,25,150,1600000000
11,24,90,1600000000
EOF

cat << 'EOF' > /app/corpora/evil/evil1.csv
source_id,target_id,weight,timestamp
10,25,50,1600000000
3,4,80,1600000000
10,11,99,1600000000
EOF

cat << 'EOF' > /app/raw_graph.csv
source_id,target_id,weight,timestamp
1,2,50,1600
1,6,40,1601
1,3,200,1602
1,4,150,1603
1,5,100,1604
2,5,80,1605
2,6,200,1606
2,7,150,1607
2,8,300,1608
3,4,50,1609
3,11,90,1610
3,5,600,1611
4,3,10,1612
4,10,10,1613
4,17,20,1614
5,1,100,1615
5,2,10,1616
5,3,20,1617
6,1,50,1618
EOF

convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'CORRUPTION SIGNATURE: weight < 100 AND (source_id + target_id) % 7 == 0'" /app/corruption_rule.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
