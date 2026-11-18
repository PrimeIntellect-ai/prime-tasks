#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app

    # Generate the audio file using gTTS and ffmpeg
    python3 -c "
from gtts import gTTS
text = 'Experiment one. Learning rate zero point zero one, batch size sixteen, loss two point zero six. Experiment two. Learning rate zero point zero one, batch size thirty two, loss two point two two. Experiment three. Learning rate zero point zero five, batch size sixteen, loss one point six six. Experiment four. Learning rate zero point zero five, batch size thirty two, loss one point eight two. Experiment five. Learning rate zero point one, batch size sixteen, loss one point one six. Experiment six. Learning rate zero point one, batch size thirty two, loss one point three two.'
tts = gTTS(text)
tts.save('/app/experiment_log.mp3')
"
    ffmpeg -i /app/experiment_log.mp3 /app/experiment_log.wav
    rm /app/experiment_log.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
