#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/writer.py
import time
import fcntl
import tarfile
import zipfile
import io
import os

gcode_content = b"""G28
G1 X10 Y10 Z0.2
G1 X20 Y20 Z15.5
G0 F3000 Z154.2
G1 X10 Y10 Z154.2
G0 Z10.0
"""

# Create the inner zip in memory
zip_buffer = io.BytesIO()
with zipfile.ZipFile(zip_buffer, 'w') as zf:
    zf.writestr('layer_data.gcode', gcode_content)
zip_data = zip_buffer.getvalue()

open('/home/user/shared.lock', 'w').close()

while True:
    with open('/home/user/shared.lock', 'a') as lockfile:
        fcntl.flock(lockfile, fcntl.LOCK_EX)

        # Write data.tar.gz
        with tarfile.open('/home/user/data.tar.gz', 'w:gz') as tar:
            tarinfo = tarfile.TarInfo(name='inner.zip')
            tarinfo.size = len(zip_data)
            tar.addfile(tarinfo, io.BytesIO(zip_data))

        fcntl.flock(lockfile, fcntl.LOCK_UN)
    time.sleep(0.1)
EOF

chmod +x /home/user/writer.py

# Run the writer briefly to ensure the files are created during the build phase
python3 /home/user/writer.py >/dev/null 2>&1 &
WRITER_PID=$!
sleep 2
kill $WRITER_PID || true

# Add a startup script so the background process runs when the container starts
cat << 'EOF' > /.singularity.d/env/99-writer.sh
if ! ps aux | grep -v grep | grep -q "python3 /home/user/writer.py"; then
    python3 /home/user/writer.py >/dev/null 2>&1 &
fi
EOF
chmod +x /.singularity.d/env/99-writer.sh

chmod -R 777 /home/user
