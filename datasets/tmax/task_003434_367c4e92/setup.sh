#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
Timestamp,PatientID,PatientName,Condition,HeartRate,Notes
2023-10-01 08:00:00,P01,Alice Smith,Cardiac,72,"Patient slept well"
2023-10-01 14:00:00,P01,Alice Smith,Cardiac,76,"Slight discomfort
but stable"
2023-10-03 09:00:00,P01,Alice Smith,Cardiac,70,"Checkup"
2023-10-01 08:30:00,P02,Bob Jones,Cardiac,80,"Normal"
2023-10-02 08:30:00,P02,Bob Jones,Cardiac,82,"Normal"
2023-10-03 08:30:00,P02,Bob Jones,Cardiac,81,"Normal"
2023-10-01 10:00:00,P03,Carol White,Resp,90,"Wheezing
Needs inhaler"
2023-10-03 10:00:00,P03,Carol White,Resp,88,"Better"
2023-10-02 11:00:00,P04,David Brown,Resp,85,"Okay"
2023-10-03 11:00:00,P04,David Brown,Resp,86,"Okay"
2023-10-01 12:00:00,P05,Eve Davis,Resp,95,"High HR"
2023-10-03 12:00:00,P05,Eve Davis,Resp,92,"Improving"
EOF

    chmod -R 777 /home/user
