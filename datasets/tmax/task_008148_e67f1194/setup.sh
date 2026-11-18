#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/schema_deps.txt
monthly_sales_report regional_sales_view
regional_sales_view clean_transactions
clean_transactions raw_transactions
fraud_alerts_view raw_transactions
user_activity_summary raw_transactions
marketing_dashboard regional_sales_view
executive_summary monthly_sales_report
executive_summary user_activity_summary
inventory_forecast clean_transactions
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
