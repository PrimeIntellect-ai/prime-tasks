#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/project_logs
    mkdir -p /home/user/artifacts
    mkdir -p /home/user/quarantine

    cat << 'EOF' > /home/user/project_logs/validation_1.log
[2023-10-24T12:00:00Z]
Level: INFO
Event: ArtifactValidation
ArtifactID: bin-00001
Reason: Success
---
[2023-10-24T12:05:00Z]
Level: ERROR
Event: ArtifactValidation
ArtifactID: bin-00002
Reason: Checksum mismatch
---
[2023-10-24T12:10:00Z]
Level: ERROR
Event: NetworkFailure
ArtifactID: bin-00003
Reason: Timeout
EOF

    cat << 'EOF' > /home/user/project_logs/validation_2.log
[2023-10-25T08:00:00Z]
ArtifactID: bin-00004
Reason: Checksum mismatch
Level: ERROR
Event: ArtifactValidation
---
[2023-10-25T08:15:00Z]
Level: ERROR
Event: ArtifactValidation
ArtifactID: bin-00005
Reason: Format invalid
EOF

    for id in bin-00001 bin-00002 bin-00003 bin-00004 bin-00005; do
        dd if=/dev/urandom of=/home/user/artifacts/${id}.dat bs=1024 count=1 2>/dev/null
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
