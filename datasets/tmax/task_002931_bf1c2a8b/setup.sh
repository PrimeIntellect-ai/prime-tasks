#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest requests packaging

    mkdir -p /home/user/pipeline_defs

    cat << 'EOF' > /home/user/pipeline_defs/task_A.json
{
  "name": "task_A",
  "depends_on": ["task_B"],
  "requires": {
    "gcc": ">=9.0.0, <11.0.0"
  }
}
EOF

    cat << 'EOF' > /home/user/pipeline_defs/task_B.json
{
  "name": "task_B",
  "depends_on": ["task_C"],
  "requires": {
    "python": ">=3.8.0"
  }
}
EOF

    cat << 'EOF' > /home/user/pipeline_defs/task_C.json
{
  "name": "task_C",
  "depends_on": ["task_D", "task_A"],
  "requires": {
    "make": ">=4.3"
  }
}
EOF

    cat << 'EOF' > /home/user/pipeline_defs/task_D.json
{
  "name": "task_D",
  "depends_on": [],
  "requires": {
    "docker": ">=20.10.0"
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
