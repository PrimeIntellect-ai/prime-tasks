#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/audit_data.ttl
@prefix : <http://example.org/audit#> .

:emp1 a :Employee ;
    :hasAdminAccess :sysA ;
    :consultsFor :vendor1 .

:emp2 a :Employee ;
    :hasAdminAccess :sysB ;
    :consultsFor :vendor2 .

:emp3 a :Employee ;
    :hasAdminAccess :sysC ;
    :consultsFor :vendor3 .

:emp4 a :Employee ;
    :hasAdminAccess :sysA ;
    :consultsFor :vendor4 .

:vendor1 a :Vendor ;
    :providesServiceTo :sysA .

:vendor2 a :Vendor ;
    :providesServiceTo :sysA .

:vendor3 a :Vendor ;
    :providesServiceTo :sysC .

:vendor4 a :Vendor ;
    :providesServiceTo :sysB .

:sysA a :System .
:sysB a :System .
:sysC a :System .
EOF

    chmod -R 777 /home/user
