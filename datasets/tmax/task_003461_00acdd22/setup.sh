#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar gzip espeak
    pip3 install pytest

    mkdir -p /app

    # Create metadata.xml in UTF-8 first
    cat << 'EOF' > /tmp/metadata_utf8.xml
<?xml version="1.0" encoding="UTF-16LE"?>
<repository>
  <artifact id="audio_1">
    <author>Dr. Aris Thorne</author>
    <description>Vocal authentication token</description>
  </artifact>
  <artifact id="image_2">
    <author>Unknown</author>
  </artifact>
</repository>
EOF

    # Convert to UTF-16LE
    iconv -f UTF-8 -t UTF-16LE /tmp/metadata_utf8.xml > /tmp/metadata.xml

    # Create nested archive
    cd /tmp
    zip internal_data.zip metadata.xml
    tar -czvf /app/repo_archive.tar.gz internal_data.zip

    # Generate audio artifact
    espeak -w /app/artifact.wav "Sunflower is the designated code."

    # Cleanup
    rm -f /tmp/metadata_utf8.xml /tmp/metadata.xml /tmp/internal_data.zip

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
