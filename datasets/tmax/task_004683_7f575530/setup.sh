#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_temp/part1 /home/user/setup_temp/part2

    # Create ISO-8859-1 encoded files
    echo -n "Leçon un: L'intégration des systèmes." | iconv -f UTF-8 -t ISO-8859-1 > /home/user/setup_temp/part1/doc_sys.txt
    echo -n "Leçon deux: Les réseaux et la sécurité." | iconv -f UTF-8 -t ISO-8859-1 > /home/user/setup_temp/part2/doc_net.txt

    # Create CSV metadata
    echo "doc_sys.txt,Jean Dupont,2018-05-12" > /home/user/setup_temp/part1/meta1.csv
    echo "doc_net.txt,Marie Curie,2019-11-23" > /home/user/setup_temp/part2/meta2.csv

    # Create nested archives
    cd /home/user/setup_temp
    tar -czf part1.tar.gz part1/
    tar -czf part2.tar.gz part2/

    # Create outer zip
    zip /home/user/docs_archive.zip part1.tar.gz part2.tar.gz

    # Cleanup
    rm -rf /home/user/setup_temp

    chmod -R 777 /home/user
