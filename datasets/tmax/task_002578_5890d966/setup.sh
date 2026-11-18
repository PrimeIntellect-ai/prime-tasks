#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/node_classifications.txt
CustomerDB:Sensitive
FinancialDB:Sensitive
AuthService:Internal
MetricAggregator:Internal
LogForwarder:Public
AnalyticsDB:Internal
ExternalDash:Public
CacheLayer:Internal
API_Gateway:Public
EOF

    cat << 'EOF' > /home/user/raw_schema_edges.csv
CustomerDB,AuthService,Active
CustomerDB,AnalyticsDB,Active
AuthService,MetricAggregator,Active
MetricAggregator,LogForwarder,Active
AnalyticsDB,ExternalDash,Inactive
AnalyticsDB,CacheLayer,Active
CacheLayer,API_Gateway,Active
FinancialDB,AuthService,Active
FinancialDB,MetricAggregator,Active
FinancialDB,LogForwarder,Inactive
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
