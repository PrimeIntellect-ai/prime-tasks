#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tar gawk util-linux
    pip3 install pytest

    mkdir -p /app

    # Create the video with exactly 1450 frames
    ffmpeg -f lavfi -i testsrc=duration=58:rate=25 -frames:v 1450 -c:v libx264 /app/experiment_feed.mp4

    # Create the tar archive with valid files
    cd /app
    touch valid_data_1.txt valid_data_2.txt
    tar -cf dataset_archive.tar valid_data_1.txt valid_data_2.txt
    rm valid_data_1.txt valid_data_2.txt

    # Append malicious paths to the tar archive using Python
    python3 -c '
import tarfile, io
with tarfile.open("/app/dataset_archive.tar", "a") as tar:
    for name in ["../../../tmp/malicious.sh", "../home/user/escape.txt"]:
        ti = tarfile.TarInfo(name)
        ti.size = 0
        tar.addfile(ti, io.BytesIO(b""))
'

    # Create the oracle script
    cat << 'EOF' > /app/oracle_filter_dataset.sh
#!/bin/bash
(
  flock -x 200
  INPUT="$1"
  STATUS=$(echo "$INPUT" | awk '{print $2}')
  if [ "$STATUS" -ge 200 ] && [ "$STATUS" -le 299 ]; then
    echo "VALID 1450"
  elif [ "$STATUS" -ge 400 ]; then
    echo "INVALID 1450"
  else
    echo "UNKNOWN 1450"
  fi
) 200>/tmp/filter.lock
EOF
    chmod +x /app/oracle_filter_dataset.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
