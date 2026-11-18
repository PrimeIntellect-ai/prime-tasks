#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    # Model Alpha: 45 Successes, 5 Failures.
    for i in $(seq 1 45); do echo "OUTCOME: 1" >> /home/user/artifacts/model_alpha.log; done
    for i in $(seq 1 5); do echo "OUTCOME: 0" >> /home/user/artifacts/model_alpha.log; done

    # Model Beta: 9 Successes, 1 Failure.
    for i in $(seq 1 9); do echo "OUTCOME: 1" >> /home/user/artifacts/model_beta.log; done
    for i in $(seq 1 1); do echo "OUTCOME: 0" >> /home/user/artifacts/model_beta.log; done

    # Model Gamma: 85 Successes, 15 Failures.
    for i in $(seq 1 85); do echo "OUTCOME: 1" >> /home/user/artifacts/model_gamma.log; done
    for i in $(seq 1 15); do echo "OUTCOME: 0" >> /home/user/artifacts/model_gamma.log; done

    # Model Delta: 200 Successes, 35 Failures.
    for i in $(seq 1 200); do echo "OUTCOME: 1" >> /home/user/artifacts/model_delta.log; done
    for i in $(seq 1 35); do echo "OUTCOME: 0" >> /home/user/artifacts/model_delta.log; done

    chmod -R 777 /home/user
