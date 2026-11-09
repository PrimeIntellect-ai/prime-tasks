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
