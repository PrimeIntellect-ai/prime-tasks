#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest SpeechRecognition gTTS

    mkdir -p /home/user/ticket_8831
    mkdir -p /app/ticket_8831

    # Generate the voicemail
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
import os

text = "Hey IT, it's Dave. The process signal script is broken. It completely skips the first sample of every array, making everything off by one. Also, if the input array is exactly one thousand and twenty four elements long, the script throws a buffer overflow exception and crashes. Please fix these so it perfectly matches the new oracle."
tts = gTTS(text)
tts.save("/tmp/voicemail.mp3")
os.system("ffmpeg -y -i /tmp/voicemail.mp3 -ar 16000 /app/ticket_8831/voicemail.wav")
EOF
    python3 /tmp/gen_audio.py

    # Create the buggy script
    cat << 'EOF' > /home/user/ticket_8831/process_signal.py
import sys, json
def process(data, threshold):
    result = []
    if len(data) == 1024:
        raise ValueError("Buffer overflow exception")
    # Bug: Off by one
    for i in range(1, len(data)):
        if data[i] > threshold:
            result.append(data[i])
        else:
            result.append(0.0)
    return result

if __name__ == "__main__":
    d = json.loads(sys.argv[1])
    t = float(sys.argv[2])
    print(json.dumps(process(d, t)))
EOF

    # Create the oracle
    cat << 'EOF' > /app/ticket_8831/process_oracle.py
import sys, json
def process(data, threshold):
    result = []
    for i in range(0, len(data)):
        if data[i] > threshold:
            result.append(data[i])
        else:
            result.append(0.0)
    return result

if __name__ == "__main__":
    d = json.loads(sys.argv[1])
    t = float(sys.argv[2])
    print(json.dumps(process(d, t)))
EOF

    cat << 'EOF' > /app/ticket_8831/process_oracle
#!/bin/bash
python3 /app/ticket_8831/process_oracle.py "$1" "$2"
EOF
    chmod +x /app/ticket_8831/process_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
