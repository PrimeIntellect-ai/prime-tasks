#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc gawk python3-opencv python3-numpy
    pip3 install pytest

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the video
    cat << 'EOF' > /tmp/gen_vid.py
import cv2
import numpy as np

fps = 10
loads = [45, 120, 60, 200, 180, 90, 50, 210, 100, 130]
out = cv2.VideoWriter('/app/profile_viz.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (100, 100), isColor=False)

# 0.0s to 0.9s
for _ in range(fps):
    out.write(np.full((100, 100), 0, dtype=np.uint8))

# 1.0s to 10.9s
for load in loads:
    # Flash the load for 2 frames to avoid ffmpeg timestamp rounding issues
    out.write(np.full((100, 100), load, dtype=np.uint8))
    out.write(np.full((100, 100), load, dtype=np.uint8))
    for _ in range(fps - 2):
        out.write(np.full((100, 100), 0, dtype=np.uint8))

out.release()
EOF
    python3 /tmp/gen_vid.py

    # Create oracle
    cat << 'EOF' > /opt/oracle/reference_optimizer.sh
#!/bin/bash
IFS=',' read -ra loads <<< "$1"
min=${loads[0]}
max=${loads[0]}
sum=0
count=${#loads[@]}

for val in "${loads[@]}"; do
    (( val < min )) && min=$val
    (( val > max )) && max=$val
    sum=$((sum + val))
done
avg=$((sum / count))

pop=("$min" "$max" "$avg")

for ((i=0; i<10; i++)); do
    best_t=-1
    best_fit=-1

    for t in "${pop[@]}"; do
        fit=0
        for val in "${loads[@]}"; do
            diff=$((t - val))
            (( diff < 0 )) && diff=$((diff * -1))
            fit=$((fit + diff))
        done

        if [[ $best_fit -eq -1 ]] || (( fit < best_fit )) || ( (( fit == best_fit )) && (( t < best_t )) ); then
            best_fit=$fit
            best_t=$t
        fi
    done

    pop=("$best_t" "$((best_t - 5))" "$((best_t + 5))")
done

echo "$best_t"
EOF
    chmod +x /opt/oracle/reference_optimizer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
