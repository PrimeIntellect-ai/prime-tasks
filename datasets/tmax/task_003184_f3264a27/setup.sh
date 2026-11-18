#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install --default-timeout=1000 pytest numpy opencv-python-headless

mkdir -p /app
mkdir -p /home/user

python3 -c "
import cv2
import numpy as np

fps = 30
duration = 30
total_frames = fps * duration

out = cv2.VideoWriter('/app/audit_dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (100, 100))
for i in range(total_frames):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i == 412:
        frame[:] = (0, 0, 255) # BGR for Red
    else:
        frame[:] = (0, 255, 0) # BGR for Green
    out.write(frame)
out.release()
"

python3 -c "
with open('/home/user/tx_log.csv', 'w') as f:
    f.write('timestamp_sec,tx_id,resource_id,action\n')
    f.write('1.0,1,100,ACQUIRE\n')
    f.write('2.0,2,200,ACQUIRE\n')
    f.write('3.0,3,300,ACQUIRE\n')
    f.write('4.0,1,200,WAIT\n')
    f.write('5.0,2,300,WAIT\n')
    f.write('6.0,3,100,WAIT\n')
"

python3 -c "
with open('/app/hidden_massive_log.csv', 'w') as f:
    f.write('timestamp_sec,tx_id,resource_id,action\n')
    f.write('1.0,8392,1000,ACQUIRE\n')
    f.write('2.0,10293,2000,ACQUIRE\n')
    f.write('3.0,44021,3000,ACQUIRE\n')
    f.write('4.0,99201,4000,ACQUIRE\n')
    f.write('5.0,8392,2000,WAIT\n')
    f.write('6.0,10293,3000,WAIT\n')
    f.write('7.0,44021,4000,WAIT\n')
    f.write('8.0,99201,1000,WAIT\n')
    chunk = ''.join([f'10.0,{i},5000,ACQUIRE\n10.1,{i},5000,RELEASE\n' for i in range(100000, 100000 + 2500)])
    for _ in range(1000):
        f.write(chunk)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
