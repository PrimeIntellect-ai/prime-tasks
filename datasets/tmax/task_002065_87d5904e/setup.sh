#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_dir/source_files
    mkdir -p /home/user/project_dir/organized_workspace

    echo "app code" > /home/user/project_dir/source_files/app.py
    echo "css" > /home/user/project_dir/source_files/style.css
    echo "csv data" > /home/user/project_dir/source_files/database.csv
    echo "xml config" > /home/user/project_dir/source_files/settings.xml

    cat << 'EOF' > /home/user/project_dir/deployment_manifest.json
[
  {
    "src": "app.py",
    "dest": "src/app.py",
    "link_type": "symlink"
  },
  {
    "src": "style.css",
    "dest": "assets/style.css",
    "link_type": "hardlink"
  },
  {
    "src": "database.csv",
    "dest": "../database_backup.csv",
    "link_type": "symlink"
  },
  {
    "src": "settings.xml",
    "dest": "conf/../../etc/passwd",
    "link_type": "hardlink"
  },
  {
    "src": "database.csv",
    "dest": "data/db.csv",
    "link_type": "symlink"
  },
  {
    "src": "app.py",
    "dest": "src/nested/../../../app.py",
    "link_type": "hardlink"
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
