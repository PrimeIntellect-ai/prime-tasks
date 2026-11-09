#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create oracle parser
    cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import sys

def main():
    nodes = {}
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        parts = line.split('|')
        if len(parts) == 3:
            nodes[parts[0]] = (parts[1], parts[2])

    results = []
    for start_node in nodes:
        visited = set()
        curr = start_node
        while True:
            if curr in visited:
                results.append(f"{start_node}|BROKEN")
                break
            visited.add(curr)
            if curr not in nodes:
                results.append(f"{start_node}|BROKEN")
                break
            ntype, nval = nodes[curr]
            if ntype == 'F':
                results.append(f"{start_node}|RESOLVED|{nval}")
                break
            elif ntype == 'S':
                curr = nval
            else:
                results.append(f"{start_node}|BROKEN")
                break

    results.sort()
    for r in results:
        print(r)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_parser

    # Fix ImageMagick security policy to allow text/draw
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml || true

    # Create video
    convert -size 800x600 xc:black -font DejaVu-Sans -pointsize 24 -fill white -draw "text 50,50 'FATAL: Disk space exhausted in /var/backups/loop_archive_8891f'" /tmp/frame.png
    ffmpeg -loop 1 -i /tmp/frame.png -c:v libx264 -t 5 -pix_fmt yuv420p /app/backup_dash.mp4
    rm /tmp/frame.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
