#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/architecture.ttl
@prefix ex: <http://example.org/> .

ex:AuthService ex:dependsOn ex:DatabaseCluster ;
               ex:dependsOn ex:LoggingService .

ex:PaymentService ex:dependsOn ex:DatabaseCluster ;
                  ex:dependsOn ex:AuthService ;
                  ex:dependsOn ex:LoggingService .

ex:UserService ex:dependsOn ex:DatabaseCluster ;
               ex:dependsOn ex:AuthService ;
               ex:dependsOn ex:CacheService .

ex:OrderService ex:dependsOn ex:PaymentService ;
                ex:dependsOn ex:UserService ;
                ex:dependsOn ex:DatabaseCluster ;
                ex:dependsOn ex:LoggingService .

ex:InventoryService ex:dependsOn ex:DatabaseCluster ;
                    ex:dependsOn ex:LoggingService .

ex:NotificationService ex:dependsOn ex:UserService ;
                       ex:dependsOn ex:LoggingService .

ex:ReportingService ex:dependsOn ex:DatabaseCluster ;
                    ex:dependsOn ex:OrderService ;
                    ex:dependsOn ex:PaymentService ;
                    ex:dependsOn ex:LoggingService .
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "top_services": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "service_name": {
            "type": "string",
            "pattern": "^http://example.org/.*$"
          },
          "in_degree": {
            "type": "integer",
            "minimum": 1
          }
        },
        "required": ["service_name", "in_degree"],
        "additionalProperties": false
      },
      "maxItems": 3,
      "minItems": 3
    }
  },
  "required": ["top_services"],
  "additionalProperties": false
}
EOF

    chmod -R 777 /home/user
