#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required tools
apt-get install -y ffmpeg zip unzip tar

# Create necessary directories
mkdir -p /app /home/user /opt/oracle

# Create the dummy sample video
ffmpeg -f lavfi -i testsrc=duration=1.75:rate=24 -pix_fmt yuv420p /app/system_status.mp4 -y 2>/dev/null

# Create the dummy sample archive
mkdir -p /tmp/sample_build
echo '{"encoding": "ISO-8859-1"}' > /tmp/sample_build/meta.json

mkdir -p /tmp/sample_build/logs
echo -n "First file content." | iconv -f UTF-8 -t ISO-8859-1 > /tmp/sample_build/logs/a.log
echo -n "Second file content." | iconv -f UTF-8 -t ISO-8859-1 > /tmp/sample_build/logs/b.log
cd /tmp/sample_build/logs && zip ../data.zip *.log

cd /tmp/sample_build && tar -czf /app/sample_backup.tar.gz meta.json data.zip

# Build the Oracle
cat << 'EOF' > /opt/oracle/process_backup_oracle
#!/bin/bash

ARCHIVE="$1"
VIDEO="$2"

# Count frames
FRAMES=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$VIDEO")
if [ -z "$FRAMES" ] || [ "$FRAMES" == "N/A" ]; then
  FRAMES=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 "$VIDEO")
fi

TMPDIR=$(mktemp -d)
tar -xzf "$ARCHIVE" -C "$TMPDIR"
ENCODING=$(grep -o '"encoding"\s*:\s*"[^"]*"' "$TMPDIR/meta.json" | cut -d'"' -f4)

mkdir -p "$TMPDIR/logs"
unzip -q "$TMPDIR/data.zip" -d "$TMPDIR/logs"

# Print hash signs
printf -v hashes '%*s' "$FRAMES" ''
echo "${hashes// /#}"

# Print content
for f in $(ls "$TMPDIR/logs/"*.log | sort); do
  iconv -f "$ENCODING" -t UTF-8 "$f"
done

rm -rf "$TMPDIR"
EOF
chmod +x /opt/oracle/process_backup_oracle

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
