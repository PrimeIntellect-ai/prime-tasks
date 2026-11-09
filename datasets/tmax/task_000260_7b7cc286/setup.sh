#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick bc gawk
pip3 install pytest numpy

mkdir -p /app
# Generate a test video
ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -metadata title="Test \"Video\" \\ Data" /app/video.mp4

mkdir -p /home/user/pipeline

cat << 'EOF' > /home/user/pipeline/process.sh
#!/bin/bash
VIDEO=$1
OUTPUT=$2

mkdir -p /tmp/frames
ffmpeg -i "$VIDEO" -vf "format=gray" /tmp/frames/frame_%04d.jpg 2>/dev/null

TITLE=$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$VIDEO")

THRESHOLDS=""
for f in /tmp/frames/*.jpg; do
    # extract histogram
    HIST=$(convert "$f" -format %c histogram:info:- | awk '{print $1}')
    T=$(./find_threshold.sh "$f")
    THRESHOLDS="$THRESHOLDS $T"
done

./serialize.sh "$TITLE" "$THRESHOLDS" > "$OUTPUT"
EOF

cat << 'EOF' > /home/user/pipeline/find_threshold.sh
#!/bin/bash
# ISODATA thresholding
FILE=$1
T=128
T_PREV=0

# BUG: bash integer arithmetic used for float comparison, or bad convergence logic
while true; do
    DIFF=$(echo "$T - $T_PREV" | bc | awk '{if ($1 < 0) print -$1; else print $1}')
    CONVERGED=$(awk -v diff="$DIFF" 'BEGIN { if(diff < 0.01) print 1; else print 0 }')

    if [ "$CONVERGED" -eq 1 ]; then
        break
    fi
    T_PREV=$T

    # Calculate means (stubbed out actual image processing for brevity, assume awk does it)
    # The bug is that they might truncate
    RES=$(convert "$FILE" -format "%[fx:mean*255]" info:)
    # Fake update for the sake of the exercise
    T=$(awk -v t="$T" -v m="$RES" 'BEGIN { print (t + m) / 2 }')
done
echo "$T"
EOF

cat << 'EOF' > /home/user/pipeline/serialize.sh
#!/bin/bash
TITLE=$1
THRESHOLDS=$2

# BUG: Doesn't escape TITLE
echo "{"
echo "  \"title\": \"$TITLE\","
echo "  \"frame_thresholds\": ["
FIRST=1
for T in $THRESHOLDS; do
    if [ $FIRST -eq 1 ]; then
        echo "    $T"
        FIRST=0
    else
        echo "    ,$T"
    fi
done
echo "  ]"
echo "}"
EOF

chmod +x /home/user/pipeline/*.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
