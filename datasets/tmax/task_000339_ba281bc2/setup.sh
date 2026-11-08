#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /usr/local/bin
    cat << 'EOF' > /usr/local/bin/run_workload
#!/usr/bin/env bash
while getopts "p:" opt; do
  case $opt in
    p)
      p_val=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ -z "$p_val" ]; then
    echo "Missing -p argument"
    exit 1
fi

# True function: L(p) = 1.2 * (p - 14.7)^2 + 25.0
# The minimum is at p = 14.7.
awk -v p="$p_val" 'BEGIN {
    latency = 1.2 * (p - 14.7) * (p - 14.7) + 25.0;
    printf "%.4f\n", latency;
}'
EOF
    chmod +x /usr/local/bin/run_workload

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
