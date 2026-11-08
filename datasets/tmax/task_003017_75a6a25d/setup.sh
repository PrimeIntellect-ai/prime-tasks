#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install --default-timeout=100 pytest opencv-python-headless numpy pandas

    mkdir -p /app /home/user
    useradd -m -s /bin/bash user || true

    # Generate mock video with ffmpeg
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -vf "geq=r='if(lt(mod(N,30),5),0,p(X,Y))':g='if(lt(mod(N,30),5),0,p(X,Y))':b='if(lt(mod(N,30),5),0,p(X,Y))'" -pix_fmt yuv420p /app/spectrometer_feed.mp4

    # Baseline bash script (/home/user/process_spectra.sh)
    cat << 'EOF' > /home/user/process_spectra.sh
#!/bin/bash
mkdir -p frames
ffmpeg -i /app/spectrometer_feed.mp4 -vf fps=30 frames/frame_%04d.png
echo "FrameID,PeakWavelength,MaxIntensity" > /home/user/final_spectra.csv
for f in frames/*.png; do
    python3 /home/user/deconvolve.py "$f" >> /home/user/final_spectra.csv
done
EOF
    chmod +x /home/user/process_spectra.sh

    # Baseline Python script (/home/user/deconvolve.py)
    cat << 'EOF' > /home/user/deconvolve.py
import sys
import cv2
import numpy as np

def process(frame_path):
    img = cv2.imread(frame_path, cv2.IMREAD_GRAYSCALE)
    img = img.astype(float) / 255.0

    # Intentional naive factorization that fails on near-singular (e.g., black frames)
    # y = A x -> x = (A^T A)^-1 A^T y
    A = img[:100, :100]
    y = img[:100, 100:200].mean(axis=1)

    # This crashes if A is all zeros
    AtA_inv = np.linalg.inv(A.T @ A)
    x = AtA_inv @ A.T @ y

    peak_wave = np.argmax(x)
    max_int = np.max(x)

    frame_id = frame_path.split('_')[-1].split('.')[0]
    print(f"{int(frame_id)},{peak_wave},{max_int:.4f}")

if __name__ == "__main__":
    process(sys.argv[1])
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
