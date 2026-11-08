#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl expect curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_reports
    echo "<html>Report Jan 2023</html>" > /home/user/raw_reports/cost_report_2023_01.html
    echo "<html>Report Feb 2023</html>" > /home/user/raw_reports/cost_report_2023_02.html
    echo "<html>Report Mar 2024</html>" > /home/user/raw_reports/cost_report_2024_03.html

    chmod -R 777 /home/user
