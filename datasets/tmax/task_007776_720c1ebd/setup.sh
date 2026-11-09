#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifact_repo

    # Artifact 01 (Unlocked)
    echo "binary_data_01_A7F3" > /home/user/artifact_repo/artifact_01.dat
    echo "build=1042\nstatus=success\nmodule=auth" > /home/user/artifact_repo/artifact_01.meta

    # Artifact 02 (Locked)
    echo "binary_data_02_B2E1" > /home/user/artifact_repo/artifact_02.dat
    echo "build=1043\nstatus=pending\nmodule=database" > /home/user/artifact_repo/artifact_02.meta
    touch /home/user/artifact_repo/artifact_02.lock

    # Artifact 03 (Unlocked)
    echo "binary_data_03_C9D4" > /home/user/artifact_repo/artifact_03.dat
    echo "build=1044\nstatus=success\nmodule=payment" > /home/user/artifact_repo/artifact_03.meta

    # Fix echo interpretation of \n by using printf or echo -e
    printf "build=1042\nstatus=success\nmodule=auth\n" > /home/user/artifact_repo/artifact_01.meta
    printf "build=1043\nstatus=pending\nmodule=database\n" > /home/user/artifact_repo/artifact_02.meta
    printf "build=1044\nstatus=success\nmodule=payment\n" > /home/user/artifact_repo/artifact_03.meta

    chmod -R 777 /home/user
