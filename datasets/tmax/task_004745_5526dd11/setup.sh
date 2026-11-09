#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
pip3 install pytest
pip3 install torch --index-url https://download.pytorch.org/whl/cpu
pip3 install openai-whisper

mkdir -p /app/audio
mkdir -p /app/data
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Generate audio file using espeak
espeak -w /app/audio/support_call.wav "Hello, I am locked out of my account and need a password reset. Thank you."

# Create metadata.csv
cat <<EOF > /app/data/metadata.csv
filename,customer_id,account_tier
support_call.wav,CUST-9921,Premium
other_call.wav,CUST-1022,Basic
EOF

# Create clean corpus
cat <<EOF > /app/corpus/clean/msg1.txt
My bill is too high and I need to speak to a manager.
EOF
cat <<EOF > /app/corpus/clean/msg2.txt
How do I upgrade my current plan?
EOF
cat <<EOF > /app/corpus/clean/msg3.txt
Hello, I am locked out of my account and need a password reset. Thank you.
EOF

# Create evil corpus
cat <<EOF > /app/corpus/evil/spam1.txt
Invest in bitcoin today for guaranteed returns!
EOF
cat <<EOF > /app/corpus/evil/spam2.txt
Click here to claim your free crypto investment.
EOF
cat <<EOF > /app/corpus/evil/spam3.txt
We offer guaranteed returns on all bitcoin deposits.
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
