#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk fonts-dejavu-core
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app /home/user/data

    # Generate a 120-second test video with changing visual text (time) to vary frame sizes
    ffmpeg -f lavfi -i "color=c=blue:s=320x240:d=120" -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='%{pts\:hms}':x=(w-tw)/2:y=(h-th)/2:fontsize=30:fontcolor=white" -c:v libx264 -y /app/drone_feed.mp4

    # Generate gappy telemetry.csv
    cat << 'EOF' > /home/user/data/telemetry.csv
timestamp,speed
1,12.5
2,13.0
5,15.2
10,14.1
11,14.5
15,16.0
20,18.2
45,22.1
60,20.0
80,19.5
100,15.0
115,10.0
120,0.0
EOF

    # Create Oracle Program
    cat << 'EOF' > /app/oracle_query.sh
#!/bin/bash
START=$1
END=$2

# Ensure frames exist for oracle
if [ ! -d /tmp/oracle_frames ]; then
    mkdir -p /tmp/oracle_frames
    ffmpeg -i /app/drone_feed.mp4 -vf fps=1 /tmp/oracle_frames/frame_%03d.jpg -loglevel quiet
    for i in {1..120}; do
        fname=$(printf "/tmp/oracle_frames/frame_%03d.jpg" $i)
        size=$(stat -c%s "$fname")
        echo "$i,$size" >> /tmp/oracle_sizes.csv
    done

    # Impute telemetry
    awk -F, '
    BEGIN { last_speed = 0.0; }
    NR==1 { next; }
    { data[$1] = $2; }
    END {
        for(i=1; i<=120; i++) {
            if (i in data) {
                last_speed = data[i];
            }
            print i "," last_speed > "/tmp/oracle_imputed.csv"
        }
    }
    ' /home/user/data/telemetry.csv
fi

# Calculate stats
awk -F, -v s="$START" -v e="$END" '
    ARGIND==1 { speed[$1] = $2 }
    ARGIND==2 { size[$1] = $2 }
    END {
        sum_speed = 0;
        max_size = 0;
        count = 0;
        for (i=s; i<=e; i++) {
            sum_speed += speed[i];
            if (size[i] > max_size) { max_size = size[i]; }
            count++;
        }
        avg_speed = count > 0 ? (sum_speed / count) : 0;
        printf "AverageSpeed: %.1f | MaxFrameSize: %d\n", avg_speed, max_size;
    }
' /tmp/oracle_imputed.csv /tmp/oracle_sizes.csv
EOF
    chmod +x /app/oracle_query.sh

    chmod -R 777 /home/user /app
