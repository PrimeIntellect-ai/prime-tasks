#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c "
import os, zipfile, tarfile, io

os.makedirs('/home/user/extracted', exist_ok=True)

tar1 = io.BytesIO()
with tarfile.open(fileobj=tar1, mode='w') as t:
    tinfo = tarfile.TarInfo(name='../evil.csv')
    data = b'id,name\n1,alice'
    tinfo.size = len(data)
    t.addfile(tinfo, io.BytesIO(data))

    tinfo = tarfile.TarInfo(name='safe1.csv')
    data = b'id,name\n2,bob'
    tinfo.size = len(data)
    t.addfile(tinfo, io.BytesIO(data))

tar2 = io.BytesIO()
with tarfile.open(fileobj=tar2, mode='w') as t:
    tinfo = tarfile.TarInfo(name='dir/../../../passwd.csv')
    data = b'id,name\n3,charlie'
    tinfo.size = len(data)
    t.addfile(tinfo, io.BytesIO(data))

with zipfile.ZipFile('/home/user/archive.zip', 'w') as z:
    z.writestr('data1.tar', tar1.getvalue())
    z.writestr('data2.tar', tar2.getvalue())
"

chmod -R 777 /home/user
