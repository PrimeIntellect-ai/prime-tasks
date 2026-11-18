#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle_format_alert.py
import sys, json, re

def main():
    raw = sys.stdin.read().strip()
    match = re.match(r'^\[(.*?)\]\s*(\{.*\})$', raw)
    if not match:
        print("INVALID LOG")
        return
    level, json_str = match.groups()
    try:
        data = json.loads(json_str)
        if not all(k in data for k in ("user", "action", "ip")):
            print("INVALID LOG")
            return
        print(f"ALERT LEVEL: {level}\nACTION: {data['action']}\nUSER: {data['user']}\nIP: {data['ip']}")
    except json.JSONDecodeError:
        print("INVALID LOG")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /tmp/sub.srt
1
00:00:01,000 --> 00:00:01,500
[INFO] {"user": "u1", "action": "a1", "ip": "1.1.1.1"}

2
00:00:02,000 --> 00:00:02,500
[INFO] {"user": "u2", "action": "a2", "ip": "1.1.1.2"}

3
00:00:03,000 --> 00:00:03,500
[INFO] {"user": "u3", "action": "a3", "ip": "1.1.1.3"}

4
00:00:04,000 --> 00:00:04,500
[INFO] {"user": "u4", "action": "a4", "ip": "1.1.1.4"}

5
00:00:05,000 --> 00:00:05,500
[INFO] {"user": "u5", "action": "a5", "ip": "1.1.1.5"}

6
00:00:06,000 --> 00:00:06,500
[INFO] {"user": "u6", "action": "a6", "ip": "1.1.1.6"}

7
00:00:07,000 --> 00:00:07,500
[INFO] {"user": "u7", "action": "a7", "ip": "1.1.1.7"}

8
00:00:08,000 --> 00:00:08,500
[INFO] {"user": "u8", "action": "a8", "ip": "1.1.1.8"}

9
00:00:09,000 --> 00:00:09,500
[INFO] {"user": "u9", "action": "a9", "ip": "1.1.1.9"}

10
00:00:10,000 --> 00:00:10,500
[INFO] {"user": "u10", "action": "a10", "ip": "1.1.1.10"}

11
00:00:11,000 --> 00:00:11,500
[INFO] {"user": "u11", "action": "a11", "ip": "1.1.1.11"}

12
00:00:12,000 --> 00:00:12,500
[INFO] {"user": "u12", "action": "a12", "ip": "1.1.1.12"}

13
00:00:13,000 --> 00:00:13,500
[INFO] {"user": "u13", "action": "a13"}

14
00:00:14,000 --> 00:00:14,500
[INFO] {"user": "u14", "ip": "1.1.1.14"}

15
00:00:15,000 --> 00:00:15,500
[INFO] {"action": "a15", "ip": "1.1.1.15"}

16
00:00:16,000 --> 00:00:16,500
[INFO] {malformed json}

17
00:00:17,000 --> 00:00:17,500
[INFO] {"user": "u17", "action": "a17", "ip": "1.1.1.17"

18
00:00:18,000 --> 00:00:18,500
Just some text

19
00:00:19,000 --> 00:00:19,500
More text

20
00:00:20,000 --> 00:00:20,500
Even more text

21
00:00:21,000 --> 00:00:21,500
Text 21

22
00:00:22,000 --> 00:00:22,500
Text 22

23
00:00:23,000 --> 00:00:23,500
Text 23

24
00:00:24,000 --> 00:00:24,500
Text 24

25
00:00:25,000 --> 00:00:25,500
Text 25
EOF

    ffmpeg -f lavfi -i color=c=black:s=320x240:d=26 -i /tmp/sub.srt -c:v libx264 -c:s mov_text /app/security_feed.mp4
    rm /tmp/sub.srt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
