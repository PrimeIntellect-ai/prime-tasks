#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    mkdir -p /home/user/workspace/extracted
    mkdir -p /home/user/workspace/processed

    # Create doc1.csv with ISO-8859-1 encoding (contains accents)
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/workspace/doc1.csv
id,title,status
101,Guía de usuario,Active
102,Resumé,Archived
EOF

    # Create doc2.xml with ISO-8859-1 encoding
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/workspace/doc2.xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<document>
  <section>
    <content>Introducción a la plataforma.</content>
  </section>
  <section>
    <content>Configuración de red: Módulo eléctrico.</content>
  </section>
</document>
EOF

    # Package into tar.gz
    cd /home/user/workspace
    tar -czf legacy_docs.tar.gz doc1.csv doc2.xml
    rm doc1.csv doc2.xml

    # Create mapping.json
    cat << 'EOF' > /home/user/workspace/mapping.json
{
  "doc1.csv": {
    "target_name": "metadata.json",
    "encoding": "ISO-8859-1",
    "action": "csv_to_json"
  },
  "doc2.xml": {
    "target_name": "specs.txt",
    "encoding": "ISO-8859-1",
    "action": "extract_xml_content"
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
