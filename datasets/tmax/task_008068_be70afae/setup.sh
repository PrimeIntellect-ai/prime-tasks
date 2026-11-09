#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_artifacts
    cd /home/user/incoming_artifacts

    # Create payload files
    echo "binary_data_alpha" > alpha_payload.bin
    echo "binary_data_beta" > beta_payload.bin
    echo "binary_data_gamma" > gamma_payload.bin
    echo "binary_data_delta" > delta_payload.bin

    # Create metadata files (using printf for POSIX sh compatibility)
    printf "Version: v1.0.0\nSource: http://old-repo.local/bin\n" > alpha_metadata.txt
    printf "Name: beta\nSTATUS=DRAFT\n" > beta_metadata.txt
    printf "Name: gamma\nType: Unknown\n" > gamma_metadata.txt
    printf "Name: delta\narch=x86\n" > delta_metadata.txt

    # Package artifacts
    for name in alpha beta gamma delta; do
        mkdir -p tmp_${name}
        mv ${name}_payload.bin tmp_${name}/payload.bin
        mv ${name}_metadata.txt tmp_${name}/metadata.txt
        cd tmp_${name}
        tar -czf ../${name}.tar.gz payload.bin metadata.txt
        cd ..
        rm -rf tmp_${name}
    done

    # Generate valid checksums
    sha256sum alpha.tar.gz beta.tar.gz gamma.tar.gz delta.tar.gz > checksums.sha256

    # Corrupt gamma.tar.gz to make it fail validation
    echo "corrupted" >> gamma.tar.gz

    # Create curation_rules.json in home dir
    cat << 'EOF' > /home/user/curation_rules.json
{
  "alpha": [
    {"search": "v1.0.0", "replace": "v1.1.0"},
    {"search": "http://old-repo.local", "replace": "https://secure-repo.local"}
  ],
  "beta": [
    {"search": "STATUS=DRAFT", "replace": "STATUS=PUBLISHED"}
  ],
  "delta": [
    {"search": "arch=x86", "replace": "arch=amd64"}
  ]
}
EOF

    chmod -R 777 /home/user
