#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest gTTS

mkdir -p /app/verifier/corpus/evil
mkdir -p /app/verifier/corpus/clean

# Generate audio file
python3 -c "
from gtts import gTTS
text = 'The verified sha two fifty six hash of the logs archive is d 7 a 8 f b b 3 0 7 d 7 8 0 9 4 6 9 c a 9 a b c b 0 0 8 2 e 4 f 8 d 5 6 5 1 e 4 6 d 3 c d b 7 6 2 d 0 2 d 0 b f 3 7 c 9 e 5 9 2.'
tts = gTTS(text=text, lang='en')
tts.save('/app/audit_interview.wav')
"

# Create dummy logs archive
touch /app/logs.tar.gz

# Create clean corpus
cat << 'EOF' > /app/verifier/corpus/clean/clean1.txt
User admin logged in successfully.
Failed login attempt for user guest.
System update completed at 02:00 AM.
EOF

# Create evil corpus
cat << 'EOF' > /app/verifier/corpus/evil/evil1.txt
User <script>alert(1)</script> logged in.
User update completed. SSN is 999-88-7777.
Query executed: SELECT * FROM users WHERE name = '' OR 1=1 --'
Attempted access with javascript:void(0)
Image loaded with onerror=alert(1)
SQL injection attempt: UNION SELECT username, password FROM users
Valid user logged in but SSN is 123-45-6789.
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
