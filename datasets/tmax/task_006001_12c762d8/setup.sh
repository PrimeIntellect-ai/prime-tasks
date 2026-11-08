#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/archives
    mkdir -p /home/user/unpacked
    mkdir -p /home/user/renamed
    mkdir -p /home/user/final

    cd /home/user
    mkdir -p /tmp/dataset_setup
    cd /tmp/dataset_setup

    id_counter=100
    for b in 1 2; do
      mkdir -p batch${b}
      for z in 1 2; do
        mkdir -p batch${b}/zip${z}
        for f in 1 2 3; do
          id_counter=$((id_counter + 1))
          date_str="2023-01-$(printf "%02d" ${f})"
          file="batch${b}/zip${z}/file_${f}_rand$RANDOM.txt"
          echo "META_INFO ID: ${id_counter} DATE: ${date_str}" > "$file"
          echo "# This is comment 1" >> "$file"
          echo "val${id_counter}A||val${id_counter}B||val${id_counter}C" >> "$file"
          echo "# Another comment" >> "$file"
          echo "val${id_counter}X||val${id_counter}Y||val${id_counter}Z" >> "$file"
        done
        cd batch${b}/zip${z}
        zip -q ../group${z}.zip *.txt
        cd ../..
      done
      cd batch${b}
      tar -czf ../batch${b}.tar.gz *.zip
      cd ..
    done

    mv batch1.tar.gz batch2.tar.gz /home/user/archives/
    rm -rf /tmp/dataset_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
