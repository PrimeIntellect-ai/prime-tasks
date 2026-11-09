#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/crash_trace.log
Traceback (most recent call last):
  File "/opt/service/main.py", line 142, in <module>
    run_service()
  File "/opt/service/main.py", line 98, in run_service
    process_queue()
  File "/opt/service/worker.py", line 55, in process_queue
    execute_job(job_id)
  File "/opt/service/worker.py", line 120, in execute_job
    optimize_weights()
  File "/opt/service/math_utils.py", line 45, in optimize_weights
    state.append(bytearray(1024 * 1024))  # Memory leak
MemoryError
EOF

    python3 -c '
import struct
with open("/home/user/intermediate_state.bin", "wb") as f:
    f.write(struct.pack("<f", 3.14159))
    f.write(b"Data\x80\xFFProc_Alpha")
'

    chmod -R 777 /home/user
