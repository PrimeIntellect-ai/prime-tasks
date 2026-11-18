#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar ffmpeg
    pip3 install pytest

    mkdir -p /app/data_dir
    echo "data" > /app/data_dir/file1.txt
    tar --listed-incremental=/app/backup.snar -cvzf /app/full_backup.tar.gz -C /app data_dir
    echo "new data" > /app/data_dir/file2.txt

    mkdir -p /tmp/zip_build
    echo "TargetDirectory=/app/data_dir" > /tmp/zip_build/settings.conf
    cd /tmp/zip_build
    zip /app/update.zip settings.conf
    python3 -c "import zipfile; z = zipfile.ZipFile('/app/update.zip', 'a'); z.writestr('../../../../../tmp/hacked.txt', 'hacked')"

    ffmpeg -f lavfi -i sine=frequency=1000:duration=10 /app/voice_memo.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
