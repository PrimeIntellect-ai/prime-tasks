#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    cat << 'EOF' > /app/subs.srt
1
00:00:01,000 --> 00:00:03,000
Payload: A -> Output: 0x15

2
00:00:03,500 --> 00:00:05,000
Payload: AB -> Output: 0x58

3
00:00:05,500 --> 00:00:07,000
Payload: TEST -> Output: 0x05

4
00:00:07,500 --> 00:00:09,000
Payload: HELLO -> Output: 0xb5

5
00:00:09,500 --> 00:00:11,000
Payload: DROP_TABLE -> Output: DENY

6
00:00:11,500 --> 00:00:13,000
Payload: GET_PWN -> Output: ALERT
EOF

    # Create a dummy video with the subtitle track
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=15 -i /app/subs.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/traffic_monitor.mp4

    # Create the oracle
    cat << 'EOF' > /app/oracle_hash.sh
#!/bin/bash
input="$1"
if [[ "$input" == *"DROP"* ]]; then
    echo "DENY"
    exit 1
fi
if [[ "$input" == *"PWN"* ]]; then
    echo "ALERT"
    exit 2
fi
hash=85
for (( i=0; i<${#input}; i++ )); do
  char_val=$(printf "%d" "'${input:$i:1}")
  hash=$(( (hash ^ char_val) + 1 ))
  hash=$(( hash % 256 ))
done
printf "0x%02x\n" $hash
exit 0
EOF
    chmod +x /app/oracle_hash.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
