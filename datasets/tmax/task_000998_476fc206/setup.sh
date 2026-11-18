#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest

mkdir -p /app/audio
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil
mkdir -p /home/user

# Generate the audio fixture using ffmpeg (sine wave with embedded metadata)
# The hidden threshold is 45 seconds.
ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -metadata comment="The maximum valid duration for this run is 45 seconds. Drop anything longer." /app/audio/researcher_note.wav

# --- Generate Clean Corpus ---
# Clean 1: Standard valid values
cat << 'EOF' > /app/corpora/clean/exp_001.csv
id,duration,loss,wer
101,45,0.05,12.5
102,12.5,1.2,0
EOF

# Clean 2: Edge cases but valid (duration exactly 45, loss exactly 0, wer exactly 100)
cat << 'EOF' > /app/corpora/clean/exp_002.csv
id,duration,loss,wer
103,45.0,0,100
104,0.01,0.001,99.9
EOF

# --- Generate Evil Corpus ---
# Evil 1: Missing value in loss
cat << 'EOF' > /app/corpora/evil/exp_003.csv
id,duration,loss,wer
105,30,,15
EOF

# Evil 2: Outlier duration (strictly greater than 45)
cat << 'EOF' > /app/corpora/evil/exp_004.csv
id,duration,loss,wer
106,45.1,0.5,20
EOF

# Evil 3: Negative loss
cat << 'EOF' > /app/corpora/evil/exp_005.csv
id,duration,loss,wer
107,20,-0.01,10
EOF

# Evil 4: WER out of bounds
cat << 'EOF' > /app/corpora/evil/exp_006.csv
id,duration,loss,wer
108,15,1.5,100.1
EOF

# Evil 5: Missing duration value
cat << 'EOF' > /app/corpora/evil/exp_007.csv
id,duration,loss,wer
109,,1.0,50
EOF

# Evil 6: Duration is zero or negative
cat << 'EOF' > /app/corpora/evil/exp_008.csv
id,duration,loss,wer
110,0,0.5,25
111,-5,0.5,25
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
