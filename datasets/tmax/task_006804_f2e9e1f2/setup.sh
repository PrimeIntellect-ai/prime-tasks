#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/source_files_temp
    cd /home/user/source_files_temp
    echo -e "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello World\")\n}" > server.go
    echo -e "body {\n  background-color: #f0f0f0;\n  margin: 0;\n}" > style.css
    echo -e "some outdated documentation" > ignore.txt

    # Create the nested tar.gz
    tar -czvf split_data.tar.gz server.go style.css ignore.txt

    # Split the tar.gz into multi-part
    split -b 200 split_data.tar.gz split_data.tar.gz.part

    # Prepare the main archive contents
    mkdir -p /home/user/main_archive
    mv split_data.tar.gz.part* /home/user/main_archive/
    cat << 'EOF' > /home/user/main_archive/layout.json
{
  "files": [
    {
      "name": "server.go",
      "category": "backend"
    },
    {
      "name": "style.css",
      "category": "frontend"
    }
  ]
}
EOF

    # Create the main archive
    cd /home/user/main_archive
    tar -czvf /home/user/legacy_project.tar.gz split_data.tar.gz.part* layout.json

    # Cleanup
    rm -rf /home/user/source_files_temp /home/user/main_archive

    chmod -R 777 /home/user
