#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create config.ini
    cat << 'EOF' > /home/user/config.ini
[Target]
zip_file = experiment_B.zip
csv_file = sensor_readings.csv
EOF

    # Create the data files and archives
    cd /tmp
    echo "t1,10" > other_data.csv
    echo "t2,20" >> other_data.csv
    zip experiment_A.zip other_data.csv

    echo "t1,45" > sensor_readings.csv
    echo "t2,55" >> sensor_readings.csv
    echo "t3,100" >> sensor_readings.csv
    echo "t4,200" >> sensor_readings.csv
    zip experiment_B.zip sensor_readings.csv

    tar -czf dataset.tar.gz experiment_A.zip experiment_B.zip
    mv dataset.tar.gz /home/user/dataset.tar.gz

    # Clean up tmp files
    rm -f other_data.csv sensor_readings.csv experiment_A.zip experiment_B.zip

    # Set permissions
    chmod -R 777 /home/user
