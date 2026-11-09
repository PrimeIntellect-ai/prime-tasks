#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx jsonschema

    mkdir -p /home/user

    cat << 'EOF' > /home/user/infrastructure.ttl
@prefix ex: <http://example.org/infra#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:DB1 a ex:Database ;
    ex:dbSize 100 ;
    ex:needsBackup "true"^^xsd:boolean .

ex:DB2 a ex:Database ;
    ex:dbSize 50 ;
    ex:needsBackup "false"^^xsd:boolean .

ex:DB3 a ex:Database ;
    ex:dbSize 200 ;
    ex:needsBackup "true"^^xsd:boolean .

ex:Storage1 a ex:StorageNode ;
    ex:availableCapacity 150 .

ex:Storage2 a ex:StorageNode ;
    ex:availableCapacity 500 .

ex:Switch1 a ex:NetworkDevice .
ex:Switch2 a ex:NetworkDevice .

ex:Link1 a ex:NetworkLink ;
    ex:source ex:DB1 ;
    ex:target ex:Switch1 ;
    ex:latency 10 .

ex:Link2 a ex:NetworkLink ;
    ex:source ex:DB2 ;
    ex:target ex:Switch1 ;
    ex:latency 5 .

ex:Link3 a ex:NetworkLink ;
    ex:source ex:DB3 ;
    ex:target ex:Switch2 ;
    ex:latency 12 .

ex:Link4 a ex:NetworkLink ;
    ex:source ex:Switch1 ;
    ex:target ex:Storage1 ;
    ex:latency 15 .

ex:Link5 a ex:NetworkLink ;
    ex:source ex:Switch1 ;
    ex:target ex:Switch2 ;
    ex:latency 8 .

ex:Link6 a ex:NetworkLink ;
    ex:source ex:Switch2 ;
    ex:target ex:Storage2 ;
    ex:latency 30 .

ex:Link7 a ex:NetworkLink ;
    ex:source ex:Switch2 ;
    ex:target ex:Storage1 ;
    ex:latency 40 .
EOF

    cat << 'EOF' > /home/user/output_schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "database_id": {
        "type": "string"
      },
      "target_storage_id": {
        "type": "string"
      },
      "path": {
        "type": "array",
        "items": {
          "type": "string"
        }
      },
      "total_latency": {
        "type": "integer"
      }
    },
    "required": ["database_id", "target_storage_id", "path", "total_latency"]
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
