#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create oracle script
    cat << 'EOF' > /app/oracle_lb_proxy.py
import sys, json, os

def main():
    try:
        req = json.loads(sys.argv[1])
        req_id = req["req_id"]
        size_mb = req["size_mb"]

        za = int(os.environ.get("ZONE_A_BASE", 14))
        zb = int(os.environ.get("ZONE_B_BASE", 9))
        zc = int(os.environ.get("ZONE_C_BASE", 18))

        cost_a = (za * size_mb) + (req_id % 3)
        cost_b = (zb * size_mb) + (req_id % 5)
        cost_c = (zc * size_mb) + (req_id % 2)

        costs = [("ZONE_A", cost_a), ("ZONE_B", cost_b), ("ZONE_C", cost_c)]
        costs.sort(key=lambda x: x[1])

        print(f"ROUTE_TO: {costs[0][0]}")
    except Exception:
        pass

if __name__ == "__main__":
    main()
EOF

    # Generate the video with the environment variables
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=1 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:fontsize=30:fontcolor=white:x=10:y=10:text='export ZONE_A_BASE=14\nexport ZONE_B_BASE=9\nexport ZONE_C_BASE=18'" -c:v libx264 -pix_fmt yuv420p /app/cost_demo.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
