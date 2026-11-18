#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate audio
    espeak -w /app/audio/incident_report.wav "Warning the backup rotation system is vulnerable to path traversal attacks check symlink targets immediately"

    # Generate tar files using python
    python3 -c "
import tarfile
import os

# Clean tar
with tarfile.open('/app/corpora/clean/clean1.tar', 'w') as t:
    ti = tarfile.TarInfo('safe_file.txt')
    ti.size = 0
    t.addfile(ti)

with tarfile.open('/app/corpora/clean/clean2.tar', 'w') as t:
    ti = tarfile.TarInfo('dir/safe_file.txt')
    ti.size = 0
    t.addfile(ti)
    ti2 = tarfile.TarInfo('dir/link')
    ti2.type = tarfile.SYMTYPE
    ti2.linkname = 'safe_file.txt'
    t.addfile(ti2)

# Evil tar 1: absolute path
with tarfile.open('/app/corpora/evil/evil1.tar', 'w') as t:
    ti = tarfile.TarInfo('/etc/shadow')
    ti.size = 0
    t.addfile(ti)

# Evil tar 2: ../ path
with tarfile.open('/app/corpora/evil/evil2.tar', 'w') as t:
    ti = tarfile.TarInfo('../../etc/shadow')
    ti.size = 0
    t.addfile(ti)

# Evil tar 3: absolute symlink
with tarfile.open('/app/corpora/evil/evil3.tar', 'w') as t:
    ti = tarfile.TarInfo('link1')
    ti.type = tarfile.SYMTYPE
    ti.linkname = '/etc/shadow'
    t.addfile(ti)

# Evil tar 4: ../ symlink
with tarfile.open('/app/corpora/evil/evil4.tar', 'w') as t:
    ti = tarfile.TarInfo('link2')
    ti.type = tarfile.SYMTYPE
    ti.linkname = '../etc/shadow'
    t.addfile(ti)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
