#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/upload_access.log
[2023-10-25 10:15:32] 192.168.1.55 POST /api/upload?target=dXBsb2Fkcy9pbWFnZTEucG5n HTTP/1.1 200
[2023-10-25 10:16:01] 10.0.0.5 POST /api/upload?target=Li4vLi4vLi4vZXRjL3Bhc3N3ZA== HTTP/1.1 200
[2023-10-25 10:17:45] 192.168.1.102 POST /api/upload?target=Li4vLi4vdmFyL3d3dy9odG1sL3NoZWxsLnBocA== HTTP/1.1 200
[2023-10-25 10:18:12] 10.0.0.5 POST /api/upload?target=Li4vLi4vLi4vLi4vYm9vdC9ncnViL2dydWIuY2Zn HTTP/1.1 403
[2023-10-25 10:20:05] 172.16.0.12 POST /api/upload?target=Li4vLi4vdG1wL2hpZGRlbi5zaA== HTTP/1.1 200
[2023-10-25 10:22:30] 192.168.1.55 POST /api/upload?target=dXBsb2Fkcy9wcm9maWxlLmpwZw== HTTP/1.1 200
EOF

    chmod -R 777 /home/user
