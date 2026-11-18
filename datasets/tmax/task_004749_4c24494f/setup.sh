#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar libc-bin
    pip3 install pytest

    mkdir -p /home/user/docs_project
    cd /home/user/docs_project

    # Create chapter 1 in ISO-8859-1
    echo "<<TITLE>>Introducción<</TITLE>>" > chap1.tmp
    echo "Este es el capítulo uno." >> chap1.tmp
    iconv -f UTF-8 -t ISO-8859-1 chap1.tmp | gzip > chapter1.txt.gz

    # Create chapter 2 in ISO-8859-1
    echo "<<TITLE>>Conclusión<</TITLE>>" > chap2.tmp
    echo "La documentación está completa." >> chap2.tmp
    iconv -f UTF-8 -t ISO-8859-1 chap2.tmp | gzip > chapter2.txt.gz

    # Create tarball
    tar -cf old_manuals.tar chapter1.txt.gz chapter2.txt.gz

    # Cleanup
    rm chap*.tmp chapter1.txt.gz chapter2.txt.gz

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/docs_project
    chmod -R 777 /home/user
