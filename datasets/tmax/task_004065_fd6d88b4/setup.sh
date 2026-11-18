#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    echo "Introduction to the system." > intro.md
    echo "This is the primary documentation file. It contains the most text so it will be the largest file among all extracted files. 1234567890" > "Release Notes.TXT"

    mkdir inner
    echo "API Guide Content" > "inner/API guide.md"
    echo "Sub documentation" > "inner/Sub Doc.md"
    zip -r nested1.zip inner/

    mkdir inner2
    echo "Another API guide with different content" > "inner2/api guide.md"
    echo "Binary blob" > inner2/image.png
    tar -czf nested2.tar.gz inner2/

    tar -czf /home/user/vendor_docs.tar.gz intro.md "Release Notes.TXT" nested1.zip nested2.tar.gz

    rm -rf /home/user/setup_tmp

    chmod -R 777 /home/user
