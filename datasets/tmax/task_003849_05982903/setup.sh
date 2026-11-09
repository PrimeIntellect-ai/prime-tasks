#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 e2fsprogs gawk
    pip3 install pytest pandas numpy

    mkdir -p /app
    mkdir -p /home/user/pipeline

    # Create dummy video fixture
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -c:v libx264 /app/test_run.mp4

    # Create ext4 image and add/delete the awk script
    dd if=/dev/zero of=/home/user/fs.img bs=1M count=10
    mkfs.ext4 /home/user/fs.img
    cat << 'EOF' > /tmp/process_log.awk
BEGIN { FS="=" }
/pkt_pts_time/ { print $2 }
EOF
    debugfs -w -R "write /tmp/process_log.awk process_log.awk" /home/user/fs.img
    debugfs -w -R "rm process_log.awk" /home/user/fs.img

    # Setup database
    cat << 'EOF' > /tmp/init.sql
CREATE TABLE frames (frame INTEGER, timestamp REAL, stream_id INTEGER);
CREATE TABLE events (event_id INTEGER, start REAL, end REAL, stream_id INTEGER);
EOF
    awk 'BEGIN {
        for(i=1; i<=300; i++) {
            ts=(i-1)*0.033;
            printf "INSERT INTO frames VALUES (%d, %.3f, 1);\n", i, ts;
            printf "INSERT INTO events VALUES (%d, %.3f, %.3f, 1);\n", i, ts-0.01, ts+0.01;
            printf "INSERT INTO events VALUES (%d, %.3f, %.3f, 2);\n", i+1000, ts-0.01, ts+0.01;
        }
    }' > /tmp/data.sql
    sqlite3 /home/user/pipeline/events.db < /tmp/init.sql
    sqlite3 /home/user/pipeline/events.db < /tmp/data.sql

    # Create ground truth
    echo "frame_index,timestamp,calibrated_threshold,event_count" > /app/ground_truth.csv
    awk 'BEGIN {
        for(i=1; i<=300; i++) {
            ts=(i-1)*0.033;
            printf "%d,%.3f,128,1\n", i, ts;
        }
    }' >> /app/ground_truth.csv

    # Create pipeline scripts
    cat << 'EOF' > /home/user/pipeline/parse_timestamps.sh
#!/bin/bash
ffprobe -v quiet -show_entries packet=pts_time -of default=noprint_wrappers=1:nokey=0 /app/test_run.mp4 | awk -f /home/user/pipeline/process_log.awk > /home/user/pipeline/timestamps.txt
EOF

    cat << 'EOF' > /home/user/pipeline/calibrate.sh
#!/bin/bash
low=0
high=255
while [ $low -le $high ]; do
  mid=$(( (low + high) / 2 ))
  if [ $mid -eq 128 ]; then break; fi
  if [ $mid -lt 128 ]; then low=$mid; else high=$mid; fi
done
echo "128" > /home/user/pipeline/threshold.txt
EOF

    cat << 'EOF' > /home/user/pipeline/aggregate_queries.sh
#!/bin/bash
sqlite3 /home/user/pipeline/events.db "SELECT frame, f.timestamp, 128, count(event_id) FROM frames f JOIN events e ON f.timestamp >= e.start AND f.timestamp <= e.end GROUP BY frame" > /home/user/pipeline/query_results.txt
EOF

    cat << 'EOF' > /home/user/pipeline/run_all.sh
#!/bin/bash
bash /home/user/pipeline/parse_timestamps.sh
bash /home/user/pipeline/calibrate.sh
bash /home/user/pipeline/aggregate_queries.sh
echo "frame_index,timestamp,calibrated_threshold,event_count" > /home/user/final_output.csv
cat /home/user/pipeline/query_results.txt | tr '|' ',' >> /home/user/final_output.csv
EOF

    chmod +x /home/user/pipeline/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
