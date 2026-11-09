#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import tarfile
import os
import io

os.makedirs("/home/user/docs_incoming", exist_ok=True)
os.makedirs("/home/user/quarantine", exist_ok=True)
os.makedirs("/home/user/extracted_docs", exist_ok=True)

# docA.tar (Safe)
os.makedirs("/tmp/tmpA", exist_ok=True)
with open("/tmp/tmpA/toc.csv", "w") as f:
    f.write("file,status\nchapter1.md,DRAFT\n")
with open("/tmp/tmpA/chapter1.md", "w") as f:
    f.write("This is a DRAFT document.\nDo not share this DRAFT.\n")
with tarfile.open("/home/user/docs_incoming/docA.tar", "w") as tar:
    tar.add("/tmp/tmpA/toc.csv", arcname="toc.csv")
    tar.add("/tmp/tmpA/chapter1.md", arcname="chapter1.md")

# docB.tar (Malicious - contains ../)
with tarfile.open("/home/user/docs_incoming/docB.tar", "w") as tar:
    info = tarfile.TarInfo(name="../malicious.txt")
    payload = b"malicious payload"
    info.size = len(payload)
    tar.addfile(info, io.BytesIO(payload))

# docC.tar (Safe)
os.makedirs("/tmp/tmpC", exist_ok=True)
with open("/tmp/tmpC/toc.csv", "w") as f:
    f.write("file,status\nchapter2.md,DRAFT\n")
with open("/tmp/tmpC/chapter2.md", "w") as f:
    f.write("Another DRAFT file.\nDRAFT is here.\n")
with tarfile.open("/home/user/docs_incoming/docC.tar", "w") as tar:
    tar.add("/tmp/tmpC/toc.csv", arcname="toc.csv")
    tar.add("/tmp/tmpC/chapter2.md", arcname="chapter2.md")

# docD.tar (Malicious - starts with /)
with tarfile.open("/home/user/docs_incoming/docD.tar", "w") as tar:
    info = tarfile.TarInfo(name="/etc/passwd_overwrite")
    payload = b"malicious payload 2"
    info.size = len(payload)
    tar.addfile(info, io.BytesIO(payload))
'

    chmod -R 777 /home/user
