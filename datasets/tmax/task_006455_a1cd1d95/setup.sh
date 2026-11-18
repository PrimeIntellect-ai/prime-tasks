#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest packaging semantic_version

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/environment_matrix.json
{
  "packages": {
    "lib-alpha": {
      "versions": {
        "1.0.0": {},
        "1.1.0": {},
        "1.2.0": {},
        "2.0.0": {}
      }
    },
    "lib-beta": {
      "versions": {
        "1.0.0": { "dependencies": { "lib-alpha": ">=1.0.0,<2.0.0" } },
        "2.0.0": { "dependencies": { "lib-alpha": ">=1.1.0,<2.0.0" } }
      }
    },
    "lib-gamma": {
      "versions": {
        "1.0.0": { "dependencies": { "lib-beta": ">=2.0.0,<3.0.0", "lib-alpha": "<1.2.0" } }
      }
    },
    "test-runner": {
      "versions": {
        "1.0.0": { "dependencies": { "lib-gamma": ">=1.0.0,<2.0.0" } }
      }
    }
  }
}
EOF

    chmod -R 777 /home/user
