#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk curl
    pip3 install pytest

    # Install PyTorch CPU to save download time, then whisper and edge-tts
    pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install --no-cache-dir openai-whisper edge-tts

    mkdir -p /app

    # Generate audio memo
    edge-tts --text "The calibration parameters for the theoretical model are as follows. The mean is four thousand five hundred and twenty. The standard deviation is eight hundred and fifteen." --write-media /tmp/memo.mp3
    ffmpeg -i /tmp/memo.mp3 -ar 16000 /app/experiment_memo.wav
    rm /tmp/memo.mp3

    # Create oracle script
    cat << 'EOF' > /app/oracle_fit_spectrum
#!/bin/bash
awk '
BEGIN {
    mu = 4520
    sigma = 815
    sum = 0
    c = 0
    prev = 0
}
{
    if (NR == 1) {
        D = 0
    } else {
        D = $1 - prev
        if (D < 0) D = -D
    }
    prev = $1

    f = NR
    diff = f - mu
    exponent = -(diff * diff) / (2 * sigma * sigma)
    T = exp(exponent)

    val = D - T
    if (val < 0) val = -val

    y = val - c
    t = sum + y
    c = (t - sum) - y
    sum = t
}
END {
    printf "%.6f\n", sum
}
' "$1"
EOF
    chmod +x /app/oracle_fit_spectrum

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
