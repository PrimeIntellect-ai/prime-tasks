#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create the compliance oracle binary
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *str = argv[1];

    char *contractor = strstr(str, "Contractor");
    char *pii = strstr(str, "PII");
    char *financial = strstr(str, "Financial");

    if (contractor && (pii || financial)) {
        char *proxy = strstr(str, "VPN_Proxy");
        char *audit = strstr(str, "Audit_Gateway");

        if (proxy || audit) {
            return 0; // Compliant
        } else {
            return 1; // Non-compliant
        }
    }
    return 0; // Compliant
}
EOF
    gcc -o /app/compliance_oracle /tmp/oracle.c
    strip /app/compliance_oracle
    chmod +x /app/compliance_oracle
    rm /tmp/oracle.c

    # Create corpus directories and JSON files
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/corpus/clean/clean1.json
{
  "nodes": [
    {"id": "n1", "type": "User", "label": "Contractor_Bob"},
    {"id": "n2", "type": "Gateway", "label": "Audit_Gateway"},
    {"id": "n3", "type": "Resource", "label": "PII_Data"}
  ],
  "edges": [
    {"source": "n1", "target": "n2"},
    {"source": "n2", "target": "n3"}
  ]
}
EOF

    cat << 'EOF' > /home/user/corpus/clean/clean2.json
{
  "nodes": [
    {"id": "n1", "type": "User", "label": "FTE_Alice"},
    {"id": "n2", "type": "Resource", "label": "PII_Data"}
  ],
  "edges": [
    {"source": "n1", "target": "n2"}
  ]
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil1.json
{
  "nodes": [
    {"id": "n1", "type": "User", "label": "Contractor_Charlie"},
    {"id": "n2", "type": "Role", "label": "Admin"},
    {"id": "n3", "type": "Resource", "label": "Financial_Records"}
  ],
  "edges": [
    {"source": "n1", "target": "n2"},
    {"source": "n2", "target": "n3"}
  ]
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil2.json
{
  "nodes": [
    {"id": "n1", "type": "User", "label": "Contractor_Dave"},
    {"id": "n2", "type": "Resource", "label": "PII_DB"}
  ],
  "edges": [
    {"source": "n1", "target": "n2"}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
