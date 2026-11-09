#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang flite ffmpeg
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate audio directive
    flite -t "Calculate the total number of distinct projects assigned to Alice and all employees in her management hierarchy, both direct and indirect." -o /app/audio_directive.wav

    # Create employees.csv
    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id,department
1,CEO,NULL,Exec
2,Alice,1,Engineering
3,Bob,2,Engineering
4,Charlie,2,Engineering
5,Dave,3,Engineering
6,Eve,1,Marketing
EOF

    # Create projects.csv
    cat << 'EOF' > /home/user/projects.csv
emp_id,project_name,status
2,Migration,Active
3,Migration,Active
3,API_v2,Active
4,Frontend,Active
5,Database,Active
6,AdCampaign,Active
5,Caching,Completed
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
