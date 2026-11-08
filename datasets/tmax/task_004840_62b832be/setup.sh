#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS networkx

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio file
    gtts-cli "The root node is Gamma, and the baseline score is eighty-two." --output /app/meeting.mp3
    ffmpeg -i /app/meeting.mp3 /app/meeting.wav
    rm /app/meeting.mp3

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.json
[{"source": "A", "target": "B"}]
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.json
[{"source": "X", "target": "Y"}, {"source": "Y", "target": "Z"}]
EOF

    # Evil corpus: Cycle
    cat << 'EOF' > /app/corpus/evil/evil1_cycle.json
[{"source": "A", "target": "B"}, {"source": "B", "target": "C"}, {"source": "C", "target": "A"}]
EOF

    # Evil corpus: Depth > 10 (11 edges)
    cat << 'EOF' > /app/corpus/evil/evil2_depth.json
[
  {"source": "0", "target": "1"},
  {"source": "1", "target": "2"},
  {"source": "2", "target": "3"},
  {"source": "3", "target": "4"},
  {"source": "4", "target": "5"},
  {"source": "5", "target": "6"},
  {"source": "6", "target": "7"},
  {"source": "7", "target": "8"},
  {"source": "8", "target": "9"},
  {"source": "9", "target": "10"},
  {"source": "10", "target": "11"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
