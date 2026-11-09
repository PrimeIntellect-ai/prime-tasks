#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/sensor_logs

    cat << 'EOF' > /home/user/sensor_logs/sensor_1.csv
Log_Time,Raw_Payload,QC_Flag
1600000000,SYS_OK_T:20.0C_P:1000hPa,PASS
1600000010,SYS_OK_T:21.0C_P:ERRhPa,PASS
1600000020,SYS_OK_T:ERRC_P:1010hPa,PASS
1600000030,SYS_OK_T:22.5C_P:1015hPa,FAIL
1600000040,SYS_OK_T:23.0C_P:1020hPa,PASS
EOF

    cat << 'EOF' > /home/user/sensor_logs/sensor_2.csv
Log_Time,Raw_Payload,QC_Flag
1600000000,SYS_OK_T:ERRC_P:900hPa,PASS
1600000010,SYS_OK_T:15.0C_P:910hPa,PASS
1600000020,SYS_OK_T:ERRC_P:920hPa,PASS
1600000030,SYS_OK_T:16.0C_P:ERRhPa,PASS
1600000040,SYS_OK_T:17.0C_P:940hPa,PASS
EOF

    cat << 'EOF' > /home/user/sensor_logs/sensor_3.csv
Log_Time,Raw_Payload,QC_Flag
1600000000,SYS_OK_T:10.0C_P:800hPa,PASS
1600000010,SYS_OK_T:10.5C_P:805hPa,FAIL
1600000020,SYS_OK_T:11.0C_P:ERRhPa,PASS
1600000030,SYS_OK_T:12.0C_P:820hPa,PASS
1600000040,SYS_OK_T:ERRC_P:830hPa,PASS
EOF

    cat << 'EOF' > /home/user/sensor_logs/sensor_4.csv
Log_Time,Raw_Payload,QC_Flag
1600000000,SYS_OK_T:5.0C_P:700hPa,PASS
1600000010,SYS_OK_T:5.5C_P:705hPa,PASS
1600000020,SYS_OK_T:6.0C_P:710hPa,PASS
1600000030,SYS_OK_T:ERRC_P:ERRhPa,PASS
1600000040,SYS_OK_T:7.0C_P:720hPa,PASS
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
