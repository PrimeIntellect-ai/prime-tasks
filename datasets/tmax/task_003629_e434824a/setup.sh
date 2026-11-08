#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sox libsox-fmt-all gawk bc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/audio_analyzer.sh
#!/bin/bash
# Buggy Audio Analyzer
INPUT=$1
OUTPUT=$2

# Extract raw data using sox
sox "$INPUT" -t dat - resample 100 | tail -n +3 > /tmp/raw_audio.dat

# VERY SLOW AND RECURSIVE SMOOTHING
smooth_data() {
    local line_num=$1
    local total_lines=$2
    if [ "$line_num" -ge "$total_lines" ]; then # BUG: off by one, or fails to terminate if total_lines is empty
        return
    fi
    # Reads file inefficiently over and over
    head -n $line_num /tmp/raw_audio.dat | tail -n 10 | awk '{sum+=$2; count++} END {if(count>0) print sum/count}' >> /tmp/smoothed.dat

    # Recursive call without proper exit limits for bash, causing stack overflow on large files
    smooth_data $((line_num + 1)) $total_lines
}

TOTAL=$(wc -l < /tmp/raw_audio.dat)
echo "" > /tmp/smoothed.dat
# smooth_data 1 $TOTAL  # (Agent will see this crashes bash, needs to be replaced with awk)

# Incorrect statistics
# Bug: sum of squares formula is wrong, variance = sum(X^2) - mean^2, but here it's incorrectly implemented
MEAN=$(awk '{sum+=$1} END {print sum/NR}' /tmp/smoothed.dat)
STDDEV=$(awk -v mean="$MEAN" '{sum+=($1+mean)^2} END {print sqrt(sum/NR)}' /tmp/smoothed.dat) # BUG: addition instead of subtraction

THRESHOLD=$(echo "$MEAN + 3 * $STDDEV" | bc -l)

# Output anomalies
awk -v thresh="$THRESHOLD" '{if ($1 > thresh) print NR/100}' /tmp/smoothed.dat > "$OUTPUT"
EOF
    chmod +x /app/audio_analyzer.sh

    # Create dummy audio file for testing
    sox -n -r 8000 -c 1 /app/test_audio.wav synth 300 sine 440

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
