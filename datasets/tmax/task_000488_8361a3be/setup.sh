#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y g++ make curl net-tools git

    # Setup vendored cxxopts
    mkdir -p /app/vendored
    cd /app/vendored
    git clone --depth 1 --branch v3.1.1 https://github.com/jarro2783/cxxopts.git

    # Remove #include <string> from cxxopts.hpp
    sed -i '/#include <string>/d' cxxopts/include/cxxopts.hpp

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
