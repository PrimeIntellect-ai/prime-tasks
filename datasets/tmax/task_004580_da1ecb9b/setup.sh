#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest pandas numpy

    mkdir -p /app
    espeak -w /app/metrics_dictation.wav "Measurement one: 45. Measurement two: 52. Measurement three: 48. Measurement four: 60. Measurement five: 55. Measurement six: 50. Measurement seven: 62. Measurement eight: 65. Measurement nine: 70. Measurement ten: 68."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
