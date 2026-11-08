#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib jsonschema

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/network.ttl
@prefix ex: <http://example.org/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

ex:Alice rdf:type ex:Person ;
         ex:connectedTo ex:Bob, ex:Charlie, ex:TechCorp .

ex:Bob rdf:type ex:Person ;
       ex:connectedTo ex:Alice .

ex:Charlie rdf:type ex:Person .

ex:TechCorp rdf:type ex:Organization ;
            ex:connectedTo ex:DataInc, ex:Alice .

ex:DataInc rdf:type ex:Organization ;
           ex:connectedTo ex:TechCorp, ex:Bob, ex:Charlie, ex:WebLLC .

ex:WebLLC rdf:type ex:Organization .
EOF

    cat << 'EOF' > /home/user/data/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "entity": {
        "type": "string",
        "format": "uri"
      },
      "connection_count": {
        "type": "integer",
        "minimum": 0
      }
    },
    "required": ["entity", "connection_count"],
    "additionalProperties": false
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
