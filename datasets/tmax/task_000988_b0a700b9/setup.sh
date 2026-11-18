#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/equations.csv
id,timestamp,equation,notes
1,2023-10-01T10:00:00," 3 x 4 + 5 ","easy
one"
2,2023-10-01T10:01:00,"12 / 4","division"
3,2023-10-01T10:02:00,"3   * 4   + 5","duplicate semantics"
4,2023-10-01T10:03:00," 1 + 1","simple
newline
test"
5,2023-10-01T10:04:00,"2^3","power"
6,2023-10-01T10:05:00,"2 ** 3","power dup"
7,2023-10-01T10:06:00,"100 / 10","another
division"
EOF

    chmod -R 777 /home/user
