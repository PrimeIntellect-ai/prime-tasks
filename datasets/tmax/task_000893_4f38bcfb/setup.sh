#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk
    pip3 install pytest

    mkdir -p /app

    # Generate a test video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x360:rate=30 -c:v libx264 -y /app/dashcam.mp4

    # Generate sensor_data.txt
    cat << 'EOF' > /app/sensor_data.txt
0 | 0.0 | 0.0
1 | 12.5 | 0.1
2 | 25.0 | -0.2
3 | 45.0 | 0.0
4 | 50.2 | 0.5
5 | 55.5 | -0.1
6 | 60.1 | 0.0
7 | 62.3 | 0.0
8 | 65.0 | 0.2
9 | 64.5 | -0.1
10 | 60.0 | 0.0
EOF

    # Generate weather.csv
    cat << 'EOF' > /app/weather.csv
0,Clear,22.0
1,Clear,22.1
2,Clear,22.2
3,Clear,22.5
4,Cloudy,22.4
5,Cloudy,22.3
6,Rain,21.0
7,Rain,20.8
8,Rain,20.5
9,Rain,20.4
10,Rain,20.3
EOF

    # Create the Oracle
    cat << 'EOF' > /app/oracle_generate_row.sh
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
EOF
    chmod +x /app/oracle_generate_row.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
