#!/bin/bash
declare -A seen
while read -r event_id timestamp; do
    if [[ -z "$timestamp" ]]; then continue; fi
    if [[ ${seen[$timestamp]} == 1 ]]; then
        echo "DUPLICATE $timestamp"
    else
        seen[$timestamp]=1
        hash=$(ffmpeg -ss "$timestamp" -i /app/surveillance.mp4 -vframes 1 -f image2 -c:v mjpeg -s 160x120 - 2>/dev/null | sha256sum | awk '{print $1}')
        echo "NEW $timestamp $hash"
    fi
done
