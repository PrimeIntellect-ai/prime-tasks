#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    qemu-utils \
    qemu-system-x86 \
    espeak \
    g++ \
    systemd \
    dbus \
    libpam-systemd

pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

espeak -w /app/voicemail_backup.wav "Hey, it's Alice. For the new backup sanitizer, make sure you reject any file that contains the exact string 'DROP TABLE' or the string 'rm -rf'. But, you must accept files that are perfectly fine. Actually, any file with the exact word 'AUTHORISED_BACKUP' should be accepted unless it has the bad strings. If it lacks 'AUTHORISED_BACKUP', reject it too."

for i in 1 2 3 4 5; do
  echo "AUTHORISED_BACKUP config_value=$i" > /app/corpus/clean/file$i.txt
done

echo "AUTHORISED_BACKUP DROP TABLE users;" > /app/corpus/evil/file1.txt
echo "AUTHORISED_BACKUP DROP TABLE config;" > /app/corpus/evil/file2.txt
echo "AUTHORISED_BACKUP rm -rf /" > /app/corpus/evil/file3.txt
echo "AUTHORISED_BACKUP rm -rf /var" > /app/corpus/evil/file4.txt
echo "config_value=safe" > /app/corpus/evil/file5.txt

qemu-img create -f qcow2 /app/dummy_disk.qcow2 10M

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
