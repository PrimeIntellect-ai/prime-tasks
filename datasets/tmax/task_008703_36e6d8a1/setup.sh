#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs extundelete binutils e2tools
    pip3 install pytest

    mkdir -p /home/user/legacy_project
    cd /home/user/legacy_project

    # 1. Create ext4 image and simulate a deleted file using e2tools to avoid mount issues
    dd if=/dev/zero of=backup_drive.ext4 bs=1M count=32
    mkfs.ext4 backup_drive.ext4

    echo "PARAM_A=42.5" > /tmp/calibration_params.txt
    echo "PARAM_B=99.1" >> /tmp/calibration_params.txt

    e2cp /tmp/calibration_params.txt backup_drive.ext4:/calibration_params.txt
    e2rm backup_drive.ext4:/calibration_params.txt
    rm /tmp/calibration_params.txt

    # 2. Create the C binary with numerical instability
    cat << 'EOF' > evaluator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double input = atof(argv[1]);
    // The secret threshold is 867.5309
    double threshold = 867.5309;
    double result = 1.0 / (input - threshold);
    printf("%f\n", result);
    return 0;
}
EOF
    gcc -O0 evaluator.c -o metric_evaluator
    rm evaluator.c

    # 3. Create sensor data with the exact failing input
    cat << 'EOF' > sensor_data.csv
123.45
234.56
345.67
456.78
567.89
678.90
789.01
867.5309
910.11
1024.00
EOF

    # 4. Create the dummy process_sensors.sh
    cat << 'EOF' > process_sensors.sh
#!/bin/bash
while read line; do
  ./metric_evaluator "$line"
done < sensor_data.csv
EOF
    chmod +x process_sensors.sh
    chmod +x metric_evaluator

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
