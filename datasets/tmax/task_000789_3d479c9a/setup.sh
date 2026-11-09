#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
1709999000,S1,15.5
1710003500,S1,-30.0
1710003550,S1,16.0
1710008000,S1,18.5
1710010000,S1,invalid
1710015000,S1,22.0
1710040000,S1,100.0
1710080000,S1,12.0
EOF

    cat << 'EOF' > /home/user/report_template.md
# Daily Sensor Report

* Minimum Temperature: TEMPLATEMIN
* Maximum Temperature: TEMPLATEMAX
* Average Temperature: TEMPLATEMEAN

End of report.
EOF

    # Replace placeholders with double curly braces using printf to avoid Apptainer build variable syntax
    MIN_STR=$(printf "\x7B\x7BMIN\x7D\x7D")
    MAX_STR=$(printf "\x7B\x7BMAX\x7D\x7D")
    MEAN_STR=$(printf "\x7B\x7BMEAN\x7D\x7D")

    sed -i "s/TEMPLATEMIN/$MIN_STR/g" /home/user/report_template.md
    sed -i "s/TEMPLATEMAX/$MAX_STR/g" /home/user/report_template.md
    sed -i "s/TEMPLATEMEAN/$MEAN_STR/g" /home/user/report_template.md

    chmod -R 777 /home/user
