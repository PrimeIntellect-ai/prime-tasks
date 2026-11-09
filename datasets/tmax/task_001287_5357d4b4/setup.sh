#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake wget
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor
    mkdir -p /home/user/incoming

    # Download and vendor snappy-1.1.10
    cd /app/vendor
    wget -q https://github.com/google/snappy/archive/refs/tags/1.1.10.tar.gz
    tar -xzf 1.1.10.tar.gz
    rm 1.1.10.tar.gz

    # Apply perturbation to CMakeLists.txt
    cd snappy-1.1.10
    if grep -q "set(CMAKE_CXX_STANDARD 11)" CMakeLists.txt; then
        sed -i 's/set(CMAKE_CXX_STANDARD 11)/set(CMAKE_CXX_STANDARD 98)/g' CMakeLists.txt
    else
        sed -i '1s/^/set(CMAKE_CXX_STANDARD 98)\n/' CMakeLists.txt
    fi

    # Create trigger script
    cat << 'EOF' > /home/user/trigger_incoming.sh
#!/bin/bash
for i in {1..50}; do
  # Create highly compressible dummy files (1MB of zeros)
  dd if=/dev/zero of=/tmp/dummy_${i}.bin bs=1M count=1 2>/dev/null
  mv /tmp/dummy_${i}.bin /home/user/incoming/
done
EOF
    chmod +x /home/user/trigger_incoming.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/vendor
