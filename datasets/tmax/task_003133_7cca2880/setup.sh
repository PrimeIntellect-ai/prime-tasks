#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tshark tcpdump
    pip3 install --default-timeout=100 pytest scapy opencv-python-headless scikit-image

    mkdir -p /app

    # Generate video
    ffmpeg -y -f lavfi -i testsrc=duration=20:size=640x480:rate=30 -c:v libx264 /app/camera.mp4

    # Generate pcap
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import IP, TCP, wrpcap
p1 = IP(dst="1.1.1.1")/TCP(dport=80, flags="S")
p1.time = 1000.000
p2 = IP(dst="1.1.1.2")/TCP(dport=1337, flags="S")
p2.time = 1005.432
wrpcap('/app/trigger.pcap', [p1, p2])
EOF
    python3 /tmp/gen_pcap.py

    # Extract truth evidence
    ffmpeg -y -ss 5.432 -i /app/camera.mp4 -frames:v 1 /app/truth_evidence.jpg

    # Create user and script
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/extract_evidence.sh
#!/bin/bash
# Inefficient extraction script
mkdir -p /tmp/frames
ffmpeg -i /app/camera.mp4 /tmp/frames/frame_%04d.jpg
sleep 15
cp /tmp/frames/frame_0001.jpg /home/user/evidence.jpg
EOF

    chmod +x /home/user/extract_evidence.sh
    chmod -R 777 /home/user
    chmod -R 777 /app
