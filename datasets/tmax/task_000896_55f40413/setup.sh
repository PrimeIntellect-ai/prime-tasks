#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/registry.json
{
  "packages": {
    "app_alpha": {
      "1.0.0": { "depends": { "lib_core": ">=1.0.0", "lib_net": "==2.0.0" } }
    },
    "app_beta": {
      "2.1.0": { "depends": { "lib_auth": ">=1.0.0", "lib_core": ">=1.1.0" } }
    },
    "app_gamma": {
      "3.0.0": { "depends": { "lib_core": "<=1.5.0", "lib_utils": ">=2.0.0" } }
    },
    "lib_core": {
      "1.0.0": { "depends": { "lib_utils": ">=1.0.0" } },
      "1.1.0": { "depends": { "lib_utils": ">=1.5.0" } },
      "1.2.0": { "depends": { "lib_utils": ">=1.5.0", "lib_crypto": "==1.0.0" } },
      "2.0.0": { "depends": { "lib_utils": ">=2.0.0", "lib_crypto": ">=2.0.0" } }
    },
    "lib_net": {
      "1.0.0": { "depends": {} },
      "2.0.0": { "depends": { "lib_core": "<=1.2.0" } }
    },
    "lib_auth": {
      "1.0.0": { "depends": { "lib_crypto": ">=1.0.0" } },
      "2.0.0": { "depends": { "lib_crypto": ">=2.0.0", "lib_core": ">=2.0.0" } }
    },
    "lib_utils": {
      "1.0.0": { "depends": {} },
      "1.5.0": { "depends": {} },
      "2.0.0": { "depends": {} },
      "2.1.0": { "depends": {} }
    },
    "lib_crypto": {
      "1.0.0": { "depends": {} },
      "2.0.0": { "depends": {} },
      "2.1.0": { "depends": {} }
    }
  }
}
EOF

    chmod -R 777 /home/user
