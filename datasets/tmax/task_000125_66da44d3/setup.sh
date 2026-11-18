#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr ffmpeg fonts-liberation
    pip3 install pytest

    mkdir -p /app/legacy

    cat << 'EOF' > /app/legacy/machine.py
# Legacy State Machine
# INIT_VAL = ??? # Lost during migration

def run_machine(input_str):
    val = INIT_VAL
    state = "START"

    for char in input_str:
        if state == "START":
            if char == "A":
                val = (val * 3) % 100
                state = "S1"
            elif char == "B":
                val = (val + 7) % 100
        elif state == "S1":
            if char == "A":
                val = (val * 2) % 100
                state = "START"
            elif char == "C":
                val = (val - 5) % 100
                state = "S2"
        elif state == "S2":
            val = (val + 11) % 100
            state = "START"

    return val
EOF

    ffmpeg -y -f lavfi -i color=c=black:s=640x480:d=1 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='Starting machine... INIT_VAL=57':fontcolor=white:fontsize=32:x=10:y=10" -c:v libx264 /app/legacy/demo.mp4

    cat << 'EOF' > /app/oracle_machine
#!/bin/bash
val=57
state="START"
input=$1

for (( i=0; i<${#input}; i++ )); do
    char="${input:$i:1}"
    if [ "$state" == "START" ]; then
        if [ "$char" == "A" ]; then
            val=$(( (val * 3) % 100 ))
            state="S1"
        elif [ "$char" == "B" ]; then
            val=$(( (val + 7) % 100 ))
        fi
    elif [ "$state" == "S1" ]; then
        if [ "$char" == "A" ]; then
            val=$(( (val * 2) % 100 ))
            state="START"
        elif [ "$char" == "C" ]; then
            val=$(( (val - 5) % 100 ))
            if [ $val -lt 0 ]; then val=$((val + 100)); fi
            state="S2"
        fi
    elif [ "$state" == "S2" ]; then
        val=$(( (val + 11) % 100 ))
        state="START"
    fi
done
echo $val
EOF
    chmod +x /app/oracle_machine

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
