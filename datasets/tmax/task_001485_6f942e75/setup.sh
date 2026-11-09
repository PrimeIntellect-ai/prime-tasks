#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/db /home/user/bin

    cat << 'EOF' > /home/user/logs/pipeline.log
[2023-10-14 08:12:01] [INFO] Worker 1 started batch_id=4012
[2023-10-14 08:12:05] [INFO] Worker 1 completed batch_id=4012 successfully.
[2023-10-14 08:12:06] [INFO] Worker 2 started batch_id=4013
[2023-10-14 08:12:10] [INFO] Worker 2 completed batch_id=4013 successfully.
[2023-10-14 08:12:11] [INFO] Worker 3 started batch_id=4014
[2023-10-14 08:17:11] [CRITICAL] Watchdog timeout: Worker 3 stalled indefinitely while processing batch_id=4014.
[2023-10-14 08:17:12] [INFO] Terminating Worker 3 and restarting...
[2023-10-14 08:17:15] [INFO] Worker 4 started batch_id=4015
[2023-10-14 08:17:20] [INFO] Worker 4 completed batch_id=4015 successfully.
EOF

    sqlite3 /home/user/db/workload.db << 'EOF'
CREATE TABLE measurements(batch_id INTEGER, input_value INTEGER);
BEGIN TRANSACTION;
-- Batch 4013 (Good)
INSERT INTO measurements VALUES(4013, 27);
INSERT INTO measurements VALUES(4013, 100);
INSERT INTO measurements VALUES(4013, 9876543);
-- Batch 4014 (Contains Poison)
INSERT INTO measurements VALUES(4014, 15);
INSERT INTO measurements VALUES(4014, 837);
INSERT INTO measurements VALUES(4014, 9991);
INSERT INTO measurements VALUES(4014, 100234);
INSERT INTO measurements VALUES(4014, 555555);
INSERT INTO measurements VALUES(4014, 3074457345618258605); -- The Poison Number (causes overflow * 3 + 1)
INSERT INTO measurements VALUES(4014, 8888);
INSERT INTO measurements VALUES(4014, 123456);
-- Batch 4015 (Good)
INSERT INTO measurements VALUES(4015, 77);
INSERT INTO measurements VALUES(4015, 88);
COMMIT;
EOF

    cat << 'EOF' > /home/user/bin/collatz_profiler.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

while read -r num; do
    original=$num
    steps=0
    # The bug: -ne 1 loops infinitely if n overflows to a negative number
    while [ "$num" -ne 1 ]; do
        if (( num % 2 == 0 )); then
            (( num = num / 2 ))
        else
            (( num = num * 3 + 1 ))
        fi
        (( steps++ ))
    done
    echo "Number $original took $steps steps."
done < "$1"
EOF
    chmod +x /home/user/bin/collatz_profiler.sh

    chmod -R 777 /home/user
