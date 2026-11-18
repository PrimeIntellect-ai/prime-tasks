#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest

mkdir -p /app/clean_corpus /app/evil_corpus

# 1. Generate the audio fixture
espeak -w /tmp/temp.wav "The Pearson correlation threshold for feature validation is zero point seven five."
ffmpeg -i /tmp/temp.wav -ar 16000 /app/reference_signal.wav
rm /tmp/temp.wav

# 2. Generate clean corpus
cat << 'EOF' > /app/clean_corpus/clean1.json
{
  "text": "data science pipeline",
  "metrics": [
    {"feat_A": 1.0, "feat_B": 1.1, "feat_C": 0.5},
    {"feat_A": 2.0, "feat_B": 1.9, "feat_C": 0.4},
    {"feat_A": 3.0, "feat_B": 3.2, "feat_C": 0.6}
  ]
}
EOF

# 3. Generate evil corpus (Fails Rule 1: Token count mismatch)
cat << 'EOF' > /app/evil_corpus/evil1_tokens.json
{
  "text": "data science",
  "metrics": [
    {"feat_A": 1.0, "feat_B": 1.1, "feat_C": 0.5},
    {"feat_A": 2.0, "feat_B": 1.9, "feat_C": 0.4},
    {"feat_A": 3.0, "feat_B": 3.2, "feat_C": 0.6}
  ]
}
EOF

# 4. Generate evil corpus (Fails Rule 2: Correlation <= 0.75)
cat << 'EOF' > /app/evil_corpus/evil2_corr.json
{
  "text": "data science pipeline",
  "metrics": [
    {"feat_A": 1.0, "feat_B": 3.1, "feat_C": 0.5},
    {"feat_A": 2.0, "feat_B": 1.9, "feat_C": 0.4},
    {"feat_A": 3.0, "feat_B": 0.2, "feat_C": 0.6}
  ]
}
EOF

# 5. Generate evil corpus (Fails Rule 3: Bootstrap lower bound < 0.0)
cat << 'EOF' > /app/evil_corpus/evil3_boot.json
{
  "text": "data science pipeline",
  "metrics": [
    {"feat_A": 1.0, "feat_B": 1.1, "feat_C": -0.8},
    {"feat_A": 2.0, "feat_B": 1.9, "feat_C": 0.1},
    {"feat_A": 3.0, "feat_B": 3.2, "feat_C": 0.2}
  ]
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
