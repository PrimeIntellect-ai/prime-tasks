#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy matplotlib flask opencv-python-headless

    mkdir -p /app
    # Generate a sample video file
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -pix_fmt yuv420p /app/video_sample.mp4

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_plot.py
import json
import matplotlib.pyplot as plt

def main():
    with open('/home/user/mse_results.json', 'r') as f:
        data = json.load(f)

    plt.plot(data)
    plt.title("Motion MSE")
    plt.ylabel("MSE")
    plt.xlabel("Frame Pair Index")

    # Bug: calling show() in a headless environment might crash, 
    # or clearing the figure making savefig save a blank image.
    try:
        plt.show()
    except:
        pass

    plt.savefig('/home/user/motion_plot.png')

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
