#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest pydub gTTS SpeechRecognition

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil /home/user/pipeline

    # Create metadata, corpora, and audio fixture
    python3 -c '
import os
from gtts import gTTS
from pydub import AudioSegment

# Corpora
for i in range(50):
    with open(f"/app/corpus/clean/clean_{i}.txt", "w") as f:
        f.write(f"This is clean text {i} with normal numbers like 42 and 100.")
    with open(f"/app/corpus/evil/evil_{i}.txt", "w") as f:
        f.write(f"This is evil text {i} with a secret code 1234567890123456.")

# Metadata
with open("/app/speaker_metadata.csv", "w") as f:
    f.write("start_time,end_time,speaker_id\n")
    f.write("0.0,5.0,ALPHA\n")
    f.write("5.0,10.0,BETA\n")
    f.write("10.0,15.0,ALPHA\n")

# Audio
t1 = "The fleet is moving to sector seven."
t2 = "Authentication code is four nine two eight one one three four five."
t3 = "Confirming receipt of two hundred units."

gTTS(t1).save("1.mp3")
gTTS(t2).save("2.mp3")
gTTS(t3).save("3.mp3")

a1 = AudioSegment.from_mp3("1.mp3")
a2 = AudioSegment.from_mp3("2.mp3")
a3 = AudioSegment.from_mp3("3.mp3")

def pad_to_5s(audio):
    target = 5000
    if len(audio) < target:
        return audio + AudioSegment.silent(duration=target - len(audio))
    return audio[:target]

final = pad_to_5s(a1) + pad_to_5s(a2) + pad_to_5s(a3)
final.export("/app/input_stream.wav", format="wav")

os.remove("1.mp3")
os.remove("2.mp3")
os.remove("3.mp3")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
