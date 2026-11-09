#!/bin/bash
T=$1
T_END=$((T + 1))

# 1. Sum bytes
SUM=$(ffprobe -v error -select_streams v:0 -show_entries packet=pts_time,size -of csv=p=0 /app/dashcam.mp4 | awk -F, -v t="$T" -v tend="$T_END" '{if ($1 >= t && $1 < tend) sum+=$2} END {print sum+0}')

# 2. Extract sensor data
SPEED=$(awk -F' \\| ' -v t="$T" '$1 == t {print $2}' /app/sensor_data.txt)

# 3. Extract weather data
TEMP=$(awk -F',' -v t="$T" '$1 == t {print $3}' /app/weather.csv)

echo "$T,$SUM,$SPEED,$TEMP"
