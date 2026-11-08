#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/docs_incoming

    python3 -c '
import tarfile
import io

with tarfile.open("/home/user/docs_incoming/docs.tar.gz", "w:gz") as tar:
    def add_file(name, content):
        data = content.encode("utf-8")
        info = tarfile.TarInfo(name=name)
        info.size = len(data)
        tar.addfile(tarinfo=info, fileobj=io.BytesIO(data))

    add_file("intro.md", "Introduction\n")
    add_file("api/reference.txt", "API Reference\n")
    add_file("images/logo.png", "fake png data")
    add_file("../../../../home/user/escaped.txt", "You got hacked!\n")
    add_file("/etc/passwd.override.md", "root::0:0:root:/root:/bin/bash\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
