#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    curl -sL https://github.com/bats-core/bats-core/archive/refs/tags/v1.8.2.tar.gz | tar -xz -C /app

    sed -i '/^fi$/a \ \ jobs=1 # DEBUG: force single job' /app/bats-core-1.8.2/libexec/bats-core/bats-exec-suite

    mkdir -p /home/user/web-sec-tests
    for i in $(seq 1 24); do
cat <<EOF > /home/user/web-sec-tests/test_$i.bats
@test "Web Security Check $i - Rate Limiting & Checksum Validation" {
  sleep 1
  [ 1 -eq 1 ]
}
EOF
    done

    chown -R user:user /home/user/web-sec-tests
    chown -R user:user /app/bats-core-1.8.2

    chmod -R 777 /home/user
