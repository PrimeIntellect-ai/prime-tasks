#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata gawk
    pip3 install pytest pandas

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/generate_logs.py
import datetime
import random
import calendar

# America/New_York offsets:
# EST = UTC-5
# EDT = UTC-4 (Starts second Sunday in March, ends first Sunday in Nov)
# 2023: March 12 (DST starts), Nov 5 (DST ends)

def gen_day(y, m, d, tz_offset_hours, users_count):
    start_dt = datetime.datetime(y, m, d, 0, 0, 0)
    start_ts = calendar.timegm(start_dt.timetuple()) - (tz_offset_hours * 3600)

    events = []
    for _ in range(users_count):
        ts = start_ts + random.randint(0, 86399)
        uid = f"user_{random.randint(1000, 9999)}"
        events.append((ts, uid))
    return events

events = []
# March 10, 11 (EST, UTC-5)
events.extend(gen_day(2023, 3, 10, -5, 100))
events.extend(gen_day(2023, 3, 11, -5, 105))
# March 12 (DST starts)
events.extend(gen_day(2023, 3, 12, -4, 95)) 
events.extend(gen_day(2023, 3, 13, -4, 102))

# Nov 3, 4 (EDT, UTC-4)
events.extend(gen_day(2023, 11, 3, -4, 110))
events.extend(gen_day(2023, 11, 4, -4, 108))
# Nov 5 (DST ends)
events.extend(gen_day(2023, 11, 5, -5, 115))
events.extend(gen_day(2023, 11, 6, -5, 100))

events.sort(key=lambda x: x[0])

with open('/home/user/pipeline/events.log', 'w') as f:
    for ts, uid in events:
        f.write(f"{int(ts)} {uid}\n")
EOF

    python3 /home/user/pipeline/generate_logs.py

    cat << 'EOF' > /home/user/pipeline/process.sh
#!/bin/bash
INPUT="events.log"
OUTPUT="report.csv"

echo "date,dau" > "$OUTPUT"

while read -r ts uid; do
    # BUG: uses default system timezone (UTC in the container) instead of America/New_York
    day=$(date -d "@$ts" +%Y-%m-%d)
    echo "$day $uid"
done < "$INPUT" | sort -u | awk '{print $1}' | uniq -c | awk '{print $2","$1}' >> "$OUTPUT"
EOF
    chmod +x /home/user/pipeline/process.sh

    cat << 'EOF' > /home/user/pipeline/Dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y tzdata
# Container defaults to UTC
WORKDIR /app
COPY process.sh .
COPY events.log .
CMD ["bash", "process.sh"]
EOF

    cat << 'EOF' > /home/user/pipeline/docker-compose.yml
version: '3'
services:
  pipeline:
    build: .
    volumes:
      - .:/app
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
