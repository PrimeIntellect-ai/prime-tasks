#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/setup_temp/set1 /home/user/setup_temp/set2
    cd /home/user

    # Create valid files (with TECHDOC\x00 header)
    printf "TECHDOC\x00Welcome to [COMPANY_V1]. This is doc1." > setup_temp/set1/doc1.txt
    printf "TECHDOC\x00[COMPANY_V1] provides great tools. [COMPANY_V1] is the best." > setup_temp/set1/doc2.txt
    printf "TECHDOC\x00Footer of [COMPANY_V1] doc." > setup_temp/set2/docA.txt

    # Create invalid files (wrong or missing header)
    printf "BADDOC\x00This is a bad doc for [COMPANY_V1]." > setup_temp/set1/bad1.txt
    printf "Just some random text without header." > setup_temp/set2/random.txt

    # Zip the sets
    cd setup_temp/set1 && zip -q ../../set1.zip * && cd ../..
    cd setup_temp/set2 && zip -q ../../set2.zip * && cd ../..

    # Tar the zips
    tar -cf legacy_docs.tar set1.zip set2.zip

    # Cleanup
    rm -rf setup_temp set1.zip set2.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
