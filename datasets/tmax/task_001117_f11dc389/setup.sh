#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg bc gawk
pip3 install pytest

mkdir -p /app

# Generate a test wav file with some noise and some absolute silence
ffmpeg -y -f lavfi -i "anoisesrc=d=1:c=pink:a=0.5" -f lavfi -i "anullsrc=r=44100:cl=mono:d=1" -f lavfi -i "sine=f=440:d=1" -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]" -map "[out]" /app/alert_log.wav

# Create process_alert.sh
cat << 'EOF' > /app/process_alert.sh
#!/bin/bash

AUDIO_FILE="/app/alert_log.wav"
OUTPUT_FILE="/home/user/smoothed_levels.txt"

> "$OUTPUT_FILE"

# Extract RMS levels per frame
levels=$(ffmpeg -i "$AUDIO_FILE" -af astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level -f null - 2>&1 | awk -F'=' '/RMS_level/ {print $2}')

window_size=5
history=()

for level in $levels; do
    history+=("$level")

    # Keep only the last 5 elements
    if [ ${#history[@]} -gt $window_size ]; then
        history=("${history[@]:1}")
    fi

    sum=0
    for val in "${history[@]}"; do
        sum=$(echo "$sum + $val" | bc -l)
    done

    # BUG: Always divides by window_size (5) even if array has fewer elements
    avg=$(echo "$sum / $window_size" | bc -l)

    # Format to 4 decimal places
    printf "%.4f\n" "$avg" >> "$OUTPUT_FILE"
done
EOF

chmod +x /app/process_alert.sh

# Create verify.py
cat << 'EOF' > /tmp/verify.py
import sys
import subprocess

def get_true_levels(audio_path):
    cmd = "ffmpeg -i " + audio_path + " -af astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level -f null - 2>&1 | awk -F'=' '/RMS_level/ {print $2}'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    levels = []
    for line in result.stdout.strip().split('\n'):
        if not line: continue
        val = line.strip()
        if val == '-inf':
            levels.append(-100.0)
        else:
            levels.append(float(val))
    return levels

def calc_sma(levels, window=5):
    sma = []
    for i in range(len(levels)):
        start = max(0, i - window + 1)
        sub = levels[start:i+1]
        sma.append(sum(sub) / len(sub))
    return sma

def main():
    agent_file = "/home/user/smoothed_levels.txt"
    try:
        with open(agent_file, 'r') as f:
            agent_vals = [float(line.strip()) for line in f.readlines() if line.strip()]
    except Exception as e:
        print(f"Error reading {agent_file}: {e}")
        sys.exit(1)

    true_levels = get_true_levels("/app/alert_log.wav")
    true_sma = calc_sma(true_levels)

    if len(agent_vals) != len(true_sma):
        print(f"Length mismatch: Agent has {len(agent_vals)}, expected {len(true_sma)}")
        sys.exit(1)

    errors = [abs(a - t) for a, t in zip(agent_vals, true_sma)]
    mae = sum(errors) / len(errors)

    print(f"MAE: {mae}")

    if mae <= 0.05:
        print("Success: MAE threshold met.")
        sys.exit(0)
    else:
        print("Failure: MAE exceeds 0.05 threshold.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
