#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils grep gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments/run_01
    mkdir -p /home/user/experiments/run_02
    mkdir -p /home/user/experiments/run_03
    mkdir -p /home/user/experiments/run_04
    mkdir -p /home/user/experiments/run_05

    printf "true_label,prediction\n1,1\n0,0\n1,0\n0,0\n1,1\n" > /home/user/experiments/run_01/predictions.csv
    printf "true_label,prediction\n1,1.0\n0,0.0\n1,NaN\n0,0.0\n1,1.0\n" > /home/user/experiments/run_02/predictions.csv
    printf "true_label,prediction\n0,1\n0,0\n1,1\n1,1\n0,0\n" > /home/user/experiments/run_03/predictions.csv
    printf "true_label,prediction\n1.5,1.2\n0.3,0.4\n1.1,1.8\n0.0,-0.1\n2.1,2.0\n" > /home/user/experiments/run_04/predictions.csv
    printf "true_label,prediction\n1,0\n1,1\n0,0\n0,1\n1,1\n" > /home/user/experiments/run_05/predictions.csv

    chown -R user:user /home/user/experiments
    chmod -R 777 /home/user
