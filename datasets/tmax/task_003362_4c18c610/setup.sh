#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Generate the video
    python3 -c "
import cv2
import numpy as np

fps = 60
duration = 2.0
f = 2.5
frames = int(fps * duration)
out = cv2.VideoWriter('/app/signal.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (100, 100))

for i in range(frames):
    t = i / fps
    intensity = 127.5 + 127.5 * np.cos(2 * np.pi * f * t)
    frame = np.full((100, 100, 3), int(intensity), dtype=np.uint8)
    out.write(frame)
out.release()
"

    # Create fft.py
    cat << 'EOF' > /home/user/fft.py
import sys
import numpy as np

data = [float(x) for x in sys.stdin.read().split()]
fps = 60.0
fft_vals = np.fft.rfft(data)
fft_freqs = np.fft.rfftfreq(len(data), 1.0/fps)
dominant_f = fft_freqs[np.argmax(np.abs(fft_vals[1:])) + 1]
print(dominant_f)
EOF

    # Create run_model.sh
    cat << 'EOF' > /home/user/run_model.sh
#!/bin/bash
# Extract intensity using python
python3 -c "
import cv2
import sys
cap = cv2.VideoCapture('/app/signal.mp4')
while True:
    ret, frame = cap.read()
    if not ret: break
    print(frame.mean())
" | python3 /home/user/fft.py > /tmp/freq.txt

f=$(cat /tmp/freq.txt)
omega=$(echo "2 * 3.14159265 * $f" | bc -l)
omega_sq=$(echo "$omega * $omega" | bc -l)

echo -e "Time\tPosition" > /home/user/trajectory.tsv
y=1.0
v=0.0
dt=0.1
t=0.0

while (( $(echo "$t <= 2.0" | bc -l) )); do
    echo -e "$t\t$y" >> /home/user/trajectory.tsv
    # Explicit Euler
    y_new=$(echo "$y + $v * $dt" | bc -l)
    v_new=$(echo "$v - $omega_sq * $y * $dt" | bc -l)
    y=$y_new
    v=$v_new
    t=$(echo "$t + $dt" | bc -l)
done
EOF

    chmod +x /home/user/run_model.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
