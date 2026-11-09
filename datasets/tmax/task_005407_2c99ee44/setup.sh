#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk ffmpeg wget
    pip3 install pytest gTTS pydub

    mkdir -p /app

    # Generate the audio file
    cat << 'EOF' > /app/generate_audio.py
from gtts import gTTS
from pydub import AudioSegment
import os

tts = gTTS(text="19 45 88", lang='en')
tts.save("/app/recording.mp3")
sound = AudioSegment.from_mp3("/app/recording.mp3")
sound.export("/app/recording.wav", format="wav")
os.remove("/app/recording.mp3")
EOF
    python3 /app/generate_audio.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_normalize.sh
#!/bin/bash
N=$1
awk -v N="$N" -F, '
BEGIN { OFS="," }
NR==1 { print; next }
NR<=N+1 {
    for(i=1; i<=NF; i++) {
        if (NR==2) { min[i]=$i; max[i]=$i }
        else {
            if ($i < min[i]) min[i]=$i
            if ($i > max[i]) max[i]=$i
        }
    }
    data[NR] = $0
}
NR>N+1 {
    data[NR] = $0
}
END {
    for(r=2; r<=NR; r++) {
        split(data[r], row, ",")
        for(i=1; i<=NF; i++) {
            if (max[i] == min[i]) {
                val = 0.00
            } else {
                val = (row[i] - min[i]) / (max[i] - min[i])
            }
            printf "%.2f%s", val, (i==NF ? "" : OFS)
        }
        print ""
    }
}'
EOF
    chmod +x /app/oracle_normalize.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
