#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
    pip3 install pytest

    mkdir -p /home/user/audit
    cat << 'EOF' > /home/user/audit/fw_export.dat
SecurePaymentGateway|InternalAuthSys|TCP|8443|RULE-001
SecurePaymentGateway|BackendProcessor|TCP|8080|RULE-002
BackendProcessor|MetricsProxy|UDP|8125|RULE-003
InternalAuthSys|AuditLogServer|TCP|514|RULE-004
AuditLogServer|MetricsProxy|TCP|443|RULE-005
MetricsProxy|MonitoringDash|TCP|80|RULE-006
MonitoringDash|PublicInternet|TCP|443|RULE-007
BackendProcessor|InventoryDB|TCP|3306|RULE-008
InventoryDB|LegacyAPI|TCP|80|RULE-009
LegacyAPI|PublicInternet|TCP|80|RULE-010
SecurePaymentGateway|DeadEndServer|TCP|22|RULE-011
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
