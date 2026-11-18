#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the audio sample
    espeak -w /app/audio_sample.wav "Whenever you encounter a token that is exactly the word 'missing', replace it with the string 'NaN' and append the suffix '.0' to all purely numeric integer tokens in the entire string to simulate a float conversion."

    # Create the oracle tokenizer script
    cat << 'EOF' > /app/oracle_tokenizer.sh
#!/bin/bash
if [ -z "$1" ]; then
    exit 0
fi

for word in $1; do
    if [ "$word" == "missing" ]; then
        echo "NaN"
    elif [[ "$word" =~ ^[0-9]+$ ]]; then
        echo "${word}.0"
    else
        echo "$word"
    fi
done
EOF
    chmod +x /app/oracle_tokenizer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
