#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget ffmpeg
    pip3 install pytest gtts pydub

    # Install MongoDB binary
    wget -qO- https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-6.0.8.tgz | tar xz -C /usr/local --strip-components=1

    mkdir -p /app

    # Generate DBA notes audio file
    python3 -c "
from gtts import gTTS
from pydub import AudioSegment
text = 'System alert. The deadlock was traced to user U-7734. Please secure the debugging endpoint with the bearer token Omega-92-Delta.'
tts = gTTS(text)
tts.save('/app/dba_notes.mp3')
AudioSegment.from_mp3('/app/dba_notes.mp3').export('/app/dba_notes.wav', format='wav')
"
    rm -f /app/dba_notes.mp3

    # Create transactions CSV
    cat << 'EOF' > /app/transactions.csv
tx_id,user_id,resource_id,lock_type,timestamp
TX01,U-1111,RES-X,GRANTED,100
TX02,U-7734,RES-A,GRANTED,105
TX03,U-1022,RES-B,GRANTED,106
TX04,U-7734,RES-B,REQUESTED,110
TX05,U-1022,RES-A,REQUESTED,112
TX06,U-2222,RES-C,GRANTED,115
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
