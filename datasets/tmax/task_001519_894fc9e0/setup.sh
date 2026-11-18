#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr gsfonts
pip3 install pytest

mkdir -p /app/corpora/evil /app/corpora/clean

# Create clean corpus
cat << 'EOF' > /app/corpora/clean/test1.csv
event_id,source_node,target_node,transfer_value,epoch_time
1,A,B,2000,100
2,B,C,2000,110
3,C,D,2000,120
EOF

cat << 'EOF' > /app/corpora/clean/test2_slow_loop.csv
event_id,source_node,target_node,transfer_value,epoch_time
1,X,Y,6000,100
2,Y,Z,6000,120
3,Z,X,6000,180
EOF

# Create evil corpus
cat << 'EOF' > /app/corpora/evil/test1.csv
event_id,source_node,target_node,transfer_value,epoch_time
1,U,V,3000,100
2,V,W,3000,110
3,W,U,3000,150
EOF

# Image generation
convert -background white -fill black -font Courier -pointsize 24 label:"Table Definition:\nTable Name: transfer_events\nColumns:\n- event_id (VARCHAR)\n- source_node (VARCHAR)\n- target_node (VARCHAR)\n- transfer_value (DECIMAL)\n- epoch_time (INTEGER)" /app/schema.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
