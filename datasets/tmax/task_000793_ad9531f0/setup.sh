#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest opencv-python-headless

mkdir -p "/app/sample videos"

cat << 'EOF' > /app/run_processor.sh
#!/bin/bash
# Buggy shell script that breaks on spaces
for file in $(ls /app/sample\ videos/*.mp4); do
    python3 /app/video_processor.py $file /tmp/output.bin
done
EOF
chmod +x /app/run_processor.sh

cat << 'EOF' > /app/video_processor.py
import sys
import cv2
import struct

def process_video(input_path, output_path):
    cap = cv2.VideoCapture(input_path)
    frames = [] # Memory leak source: appending all frames
    intensities = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame) # Leak

    for frame in frames:
        avg_intensity = frame.mean()
        intensities.append(avg_intensity)

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', len(intensities)))
        for intensity in intensities:
            f.write(struct.pack('<f', intensity))

    cap.release()

if __name__ == "__main__":
    # Buggy parsing if args are not quoted properly in shell
    input_video = sys.argv[1]
    output_bin = sys.argv[2]
    process_video(input_video, output_bin)
EOF

cat << 'EOF' > /app/reference_oracle.py
import sys
import cv2
import struct

def process_video(input_path, output_path):
    cap = cv2.VideoCapture(input_path)
    intensities = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        intensities.append(frame.mean())

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', len(intensities)))
        for intensity in intensities:
            f.write(struct.pack('<f', intensity))

    cap.release()

if __name__ == "__main__":
    process_video(sys.argv[1], sys.argv[2])
EOF

# Generate sample video
ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 "/app/sample videos/test leak.mp4"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
