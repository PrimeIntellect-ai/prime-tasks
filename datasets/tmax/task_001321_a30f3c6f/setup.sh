#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
pip3 install pytest

mkdir -p /app
mkdir -p /opt/oracle

# Generate a sample video for testing (10 seconds, 10 fps = 100 frames)
ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=10 -c:v libx264 -pix_fmt yuv420p /app/experiment_video.mp4

# Create the oracle script
cat << 'EOF' > /opt/oracle/pipeline_oracle.sh
#!/bin/bash
video="$1"
# Read header
read header
echo "event_id,frame_idx,mean_brightness"

while IFS=',' read -r event_id frame_idx; do
    # Strip carriage returns just in case
    event_id=$(echo "$event_id" | tr -d '\r')
    frame_idx=$(echo "$frame_idx" | tr -d '\r')

    if [ -z "$frame_idx" ]; then
        continue
    fi

    # Force integer format to handle cases like "15.0" if they sneak in
    frame_int=$(printf "%.0f" "$frame_idx" 2>/dev/null)

    # Extract frame
    ffmpeg -y -v error -i "$video" -vf "select='eq(n\,${frame_int})'" -vframes 1 /tmp/fuzz_frame_$$.png

    # Calculate brightness
    brightness=$(convert /tmp/fuzz_frame_$$.png -colorspace Gray -format "%[fx:mean]" info:)

    echo "${event_id},${frame_int},${brightness}"
done
rm -f /tmp/fuzz_frame_$$.png
EOF

chmod +x /opt/oracle/pipeline_oracle.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
