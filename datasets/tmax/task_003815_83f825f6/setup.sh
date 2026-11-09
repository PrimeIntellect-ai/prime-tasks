#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk sed bc
    pip3 install pytest

    mkdir -p /app
    # Create a 30-second test video
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=1 -c:v libx264 -pix_fmt yuv420p /app/sensor_feed.mp4

    # Create the oracle script
    cat << 'EOF' > /opt/oracle_process_stream.sh
#!/usr/bin/awk -f
BEGIN {
    hist[0] = 0; hist[1] = 0; hist[2] = 0;
    count = 0;
}
{
    val = $1;
    if (val == "NaN") {
        if (count == 0) {
            imp = 0;
        } else {
            n = (count < 3) ? count : 3;
            sum = 0;
            for (i=0; i<n; i++) { sum += hist[i]; }
            imp = int(sum / n);
        }
    } else {
        imp = int(val);
    }

    # shift history
    hist[2] = hist[1];
    hist[1] = hist[0];
    hist[0] = imp;
    count++;

    if (count >= 3) {
        filter = (1 * hist[0]) + (-2 * hist[1]) + (1 * hist[2]);
    } else {
        filter = 0;
    }

    print imp "," filter;
}
EOF
    chmod +x /opt/oracle_process_stream.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
