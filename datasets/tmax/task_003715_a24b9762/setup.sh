#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sox ffmpeg
    pip3 install pytest numpy scipy

    # Create directories
    mkdir -p /home/user/parser_project
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create C file
    cat << 'EOF' > /home/user/parser_project/parser.c
int parse_cmd(const char* cmd) {
    return 0;
}
EOF

    # Create broken Makefile
    printf "all:\n\tgcc -o libparser.so parser.c\n" > /home/user/parser_project/Makefile

    # Create corpus files
    echo "ls -la" > /app/corpus/clean/1.txt
    echo "echo hello" > /app/corpus/clean/2.txt

    echo "ls -la ; rm -rf /" > /app/corpus/evil/1.txt
    echo "echo \$USER" > /app/corpus/evil/2.txt
    echo "sudo su" > /app/corpus/evil/3.txt

    # Generate DTMF audio for "8675309"
    python3 << 'EOF'
import wave, struct, math

def generate_tone(f1, f2, duration=0.2, sample_rate=8000):
    samples = []
    for i in range(int(duration * sample_rate)):
        t = float(i) / sample_rate
        val = math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)
        samples.append(int(val * 16383)) # scale to 16-bit
    return samples

dtmf_freqs = {
    '8': (852, 1336), '6': (770, 1477), '7': (852, 1209),
    '5': (770, 1336), '3': (697, 1477), '0': (941, 1336), '9': (852, 1477)
}
pin = "8675309"
all_samples = []
for digit in pin:
    f1, f2 = dtmf_freqs[digit]
    all_samples.extend(generate_tone(f1, f2))
    all_samples.extend([0]*800) # 0.1s silence

with wave.open('/app/voicemail.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(8000)
    for s in all_samples:
        w.writeframesraw(struct.pack('<h', s))
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
