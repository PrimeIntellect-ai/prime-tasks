#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg pocketsphinx
pip3 install pytest gTTS SpeechRecognition

mkdir -p /app

cat << 'EOF' > /app/regions.csv
region_id,region_name,tax_rate
1,North,0.05
2,South,0.06
3,East,0.04
4,West,0.07
5,Central,0.05
EOF

cat << 'EOF' > /app/oracle_reference.sh
#!/bin/bash
INPUT_CSV=$1
sqlite3 :memory: <<SQLITE_EOF
.mode csv
.import $INPUT_CSV edges
.import /app/regions.csv regions
.mode json
SELECT 
    e.source_node AS source,
    e.target_node AS target,
    SUM(e.amount) OVER (PARTITION BY e.source_node ORDER BY e.time ASC) AS running_total
FROM edges e
JOIN regions r ON e.region_id = r.region_id
ORDER BY e.source_node ASC, e.time ASC;
SQLITE_EOF
EOF
chmod +x /app/oracle_reference.sh

cat << 'EOF' > /tmp/make_audio.py
from gtts import gTTS
text = "Fix the cross join by joining edges and regions on region_id. Project the graph by selecting source_node and target_node. Add a window function to calculate the running_total, which is the sum of amount partitioned by source_node and ordered by time ascending. Validate your output by formatting it as a JSON array of objects with exactly three keys: source, target, and running_total. Order the final JSON array by source_node ascending, then time ascending."
tts = gTTS(text)
tts.save("/app/voicemail.mp3")
EOF
python3 /tmp/make_audio.py
ffmpeg -i /app/voicemail.mp3 -ar 16000 -ac 1 /app/voicemail.wav
rm /app/voicemail.mp3 /tmp/make_audio.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
