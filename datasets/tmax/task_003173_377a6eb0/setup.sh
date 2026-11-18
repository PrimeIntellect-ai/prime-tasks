#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest pandas numpy

    mkdir -p /app
    # Create dummy video
    head -c 1024 /dev/urandom > /app/test_video.mp4

    # Create truth.csv and the git repo setup using a Python script
    cat << 'EOF' > /tmp/setup_repo.py
import os
import subprocess
import csv

# generate truth.csv
with open('/app/truth.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['frame_id', 'x', 'y', 'w', 'h'])
    x, y, w, h = 10.0, 10.0, 50.0, 50.0
    for i in range(300):
        writer.writerow([i, x, y, w, h])
        x += 1.5
        w += 0.2
        y += 0.5
        h += 0.1

# create repo
repo = '/home/user/tracker_repo'
os.makedirs(repo, exist_ok=True)
os.chdir(repo)
subprocess.run(['git', 'init'])
subprocess.run(['git', 'checkout', '-b', 'main'])

with open('extractor.cpp', 'w') as f:
    f.write('#include <iostream>\nint main() { return 0; }\n')

with open('run_pipeline.sh', 'w') as f:
    f.write('#!/bin/bash\ng++ extractor.cpp -o ext\n./ext\npython3 tracker.py "$1" "$2"\n')
os.chmod('run_pipeline.sh', 0o755)

good_tracker = """import sys
import csv

def track(out_path):
    with open(out_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['frame_id', 'x', 'y', 'w', 'h'])
        x, y, w, h = 10.0, 10.0, 50.0, 50.0
        for i in range(300):
            writer.writerow([i, x, y, w, h])
            x += 1.5
            w += 0.2
            y += 0.5
            h += 0.1

if __name__ == '__main__':
    track(sys.argv[2])
"""

bad_tracker = good_tracker.replace('x += 1.5', 'x += int(1.5)')

with open('tracker.py', 'w') as f:
    f.write(good_tracker)

subprocess.run(['git', 'add', '.'])
subprocess.run(['git', 'config', 'user.email', 'test@example.com'])
subprocess.run(['git', 'config', 'user.name', 'Test'])
subprocess.run(['git', 'commit', '-m', 'Initial commit'])
subprocess.run(['git', 'tag', 'v1.0'])

for i in range(100):
    with open('dummy.txt', 'w') as f:
        f.write(str(i))
    subprocess.run(['git', 'add', 'dummy.txt'])
    subprocess.run(['git', 'commit', '-m', f'dummy {i}'])

with open('tracker.py', 'w') as f:
    f.write(bad_tracker)
subprocess.run(['git', 'add', 'tracker.py'])
subprocess.run(['git', 'commit', '-m', 'Update tracker logic'])

for i in range(100, 200):
    with open('dummy.txt', 'w') as f:
        f.write(str(i))
    subprocess.run(['git', 'add', 'dummy.txt'])
    subprocess.run(['git', 'commit', '-m', f'dummy {i}'])
EOF

    python3 /tmp/setup_repo.py
    rm /tmp/setup_repo.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
