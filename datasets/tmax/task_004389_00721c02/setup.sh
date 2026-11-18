#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg expect bash
    pip3 install pytest opencv-python-headless Pillow

    mkdir -p /app

    # Create trigger_alert.sh
    cat << 'EOF' > /app/trigger_alert.sh
#!/bin/bash
echo -n "Enter server uptime percentage: "
read UPTIME
echo -n "Confirm alert dispatch (y/n): "
read CONFIRM
if [ "$UPTIME" == "85.00" ] && [ "$CONFIRM" == "y" ]; then
    echo "Alert dispatched successfully."
    exit 0
else
    echo "Alert failed."
    exit 1
fi
EOF
    chmod +x /app/trigger_alert.sh

    # Generate the video
    ffmpeg -f lavfi -i color=c=0x00FF00:s=320x240:r=30 -t 8 -c:v libx264 -pix_fmt yuv420p /tmp/green1.mp4
    ffmpeg -f lavfi -i color=c=0xFF0000:s=320x240:r=30 -t 1.5 -c:v libx264 -pix_fmt yuv420p /tmp/red.mp4
    ffmpeg -f lavfi -i color=c=0x00FF00:s=320x240:r=30 -t 0.5 -c:v libx264 -pix_fmt yuv420p /tmp/green2.mp4

    cat << 'EOF' > /tmp/inputs.txt
file '/tmp/green1.mp4'
file '/tmp/red.mp4'
file '/tmp/green2.mp4'
EOF

    ffmpeg -f concat -safe 0 -i /tmp/inputs.txt -c copy /app/status_light.mp4
    rm /tmp/green1.mp4 /tmp/red.mp4 /tmp/green2.mp4 /tmp/inputs.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
