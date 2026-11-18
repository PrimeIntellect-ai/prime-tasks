#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip sed gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_jobs.log
[JOB_START]
JobID: 1045
ServerIP: 192.168.1.10
Result: SUCCESS
FilesProcessed: 4502
[JOB_END]
[JOB_START]
JobID: 1042
ServerIP: 10.0.0.55
Result: FAILED
FilesProcessed: 12
ErrorTrace: Connection timed out
at backup.core.NetworkTransmitter.send(NetworkTransmitter.java:45)
at backup.core.JobRunner.run(JobRunner.java:112)
[JOB_END]
[JOB_START]
JobID: 1048
ServerIP: 172.16.254.1
Result: SUCCESS
FilesProcessed: 8991
[JOB_END]
[JOB_START]
JobID: 1041
ServerIP: 192.168.1.10
Result: SUCCESS
FilesProcessed: 100
[JOB_END]
EOF

    chmod -R 777 /home/user
