#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app/corpus/clean/batch1
    mkdir -p /app/corpus/evil/batch1
    mkdir -p /app/corpus/evil/batch2

    # Generate audio
    python3 -c "
from gtts import gTTS
text = 'Validation rules: First, there must be absolutely no circular dependencies in the edges hierarchy. Second, when you partition the nodes by department and order them by timestamp, the rolling sum of the cost for any three consecutive nodes must be strictly less than fifty thousand. If a batch breaks either of these rules, reject it.'
tts = gTTS(text)
tts.save('/app/compliance_memo.mp3')
    "
    ffmpeg -i /app/compliance_memo.mp3 /app/compliance_memo.wav
    rm /app/compliance_memo.mp3

    # Clean batch
    cat <<EOF > /app/corpus/clean/batch1/nodes.csv
id,department,timestamp,cost
1,HR,2023-01-01,10000
2,HR,2023-01-02,10000
3,HR,2023-01-03,10000
EOF
    cat <<EOF > /app/corpus/clean/batch1/edges.csv
parent_id,child_id
1,2
2,3
EOF

    # Evil batch 1: cycle
    cat <<EOF > /app/corpus/evil/batch1/nodes.csv
id,department,timestamp,cost
1,HR,2023-01-01,10000
2,HR,2023-01-02,10000
3,HR,2023-01-03,10000
EOF
    cat <<EOF > /app/corpus/evil/batch1/edges.csv
parent_id,child_id
1,2
2,3
3,1
EOF

    # Evil batch 2: cost >= 50000
    cat <<EOF > /app/corpus/evil/batch2/nodes.csv
id,department,timestamp,cost
1,IT,2023-01-01,20000
2,IT,2023-01-02,20000
3,IT,2023-01-03,15000
EOF
    cat <<EOF > /app/corpus/evil/batch2/edges.csv
parent_id,child_id
1,2
2,3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
