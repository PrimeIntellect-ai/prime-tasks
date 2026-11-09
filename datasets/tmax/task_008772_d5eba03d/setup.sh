#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/spectrum.csv
wavelength,flux
400,5.12
401,4.95
402,5.08
403,4.88
404,5.01
405,5.15
406,4.92
407,5.04
408,5.06
409,4.98
410,5.11
411,4.90
412,5.02
413,4.97
414,5.05
415,5.09
416,4.93
417,4.99
418,5.10
419,5.03
420,5.20
421,5.50
422,6.10
423,7.40
424,9.50
425,12.80
426,14.20
427,12.50
428,9.10
429,7.20
430,6.05
431,5.40
432,5.12
433,5.08
434,4.95
EOF

    chmod -R 777 /home/user
