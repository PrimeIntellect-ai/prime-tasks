#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk coreutils
    pip3 install pytest

    # Create oracle script
    cat << 'EOF' > /opt/oracle.sh
#!/bin/bash
video="$1"
ffmpeg -i "$video" -vf "fps=1,scale=1:1,format=gray" -f image2pipe -vcodec rawvideo - 2>/dev/null | od -An -v -tu1 | tr -s ' ' '\n' | awk 'NF {val[++n] = $1}
END {
  for(i=1; i<=n; i++) {
    prev = (i==1) ? 0 : val[i-1]
    next_val = (i==n) ? 0 : val[i+1]
    curr = val[i]
    avg = (prev + curr + next_val) / 3.0
    if (avg < 85.0) print "LOW"
    else if (avg <= 170.0) print "MID"
    else print "HIGH"
  }
}'
EOF
    chmod +x /opt/oracle.sh

    # Create fixture video
    mkdir -p /app
    ffmpeg -f lavfi -i "color=c=red:d=5,format=yuv420p" -y /app/raw_data.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
