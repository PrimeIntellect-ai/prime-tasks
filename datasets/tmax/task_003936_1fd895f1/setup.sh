#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar bzip2 gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/docs_setup
    cd /tmp/docs_setup

    echo "# Introduction Draft" > intro_draft_v2.md
    echo "# API Details" > api_endpoints_wip.md
    echo "# Change history" > changelog_raw_final.md

    tar -cjf content.tar.bz2 intro_draft_v2.md api_endpoints_wip.md changelog_raw_final.md

    cat << 'EOF' > structure.json
{
  "project": "AcmeDocs",
  "version": "1.0",
  "file_mapping": [
    {
      "original": "intro_draft_v2.md",
      "published": "01_Introduction.md"
    },
    {
      "original": "api_endpoints_wip.md",
      "published": "02_API_Reference.md"
    },
    {
      "original": "changelog_raw_final.md",
      "published": "03_Changelog.md"
    }
  ]
}
EOF

    tar -czf /home/user/raw_docs.tar.gz content.tar.bz2 structure.json
    rm -rf /tmp/docs_setup

    chmod -R 777 /home/user
