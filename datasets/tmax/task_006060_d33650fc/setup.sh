#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/org_chart.ttl
@prefix ex: <http://example.org/> .
@prefix org: <http://example.org/org#> .

ex:Alice org:reportsTo ex:CEO .
ex:Eve org:reportsTo ex:CEO .
ex:Bob org:reportsTo ex:Alice .
ex:Charlie org:reportsTo ex:Bob .
ex:Dave org:reportsTo ex:Alice .
ex:Frank org:reportsTo ex:Eve .
ex:Grace org:reportsTo ex:Frank .
EOF

    chmod -R 777 /home/user
