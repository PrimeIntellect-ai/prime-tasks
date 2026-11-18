#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick nginx
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /opt/verifier/clean
    mkdir -p /opt/verifier/evil

    # Generate invoice image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"FINOPS POLICY UPDATE\nAPPROVED_FAMILIES: t4g, m6g, c6g\nMAX_DEPLOYMENT_COST: 1200\nEND OF REPORT" /app/invoice_summary.png

    # Create clean corpus
    cat << 'EOF' > /opt/verifier/clean/clean1.json
{
  "app_name": "api-service",
  "instances": [
    {"type": "t4g.medium", "count": 4, "monthly_cost_per_unit": 30},
    {"type": "m6g.large", "count": 1, "monthly_cost_per_unit": 100}
  ]
}
EOF

    cat << 'EOF' > /opt/verifier/clean/clean2.json
{
  "app_name": "web-service",
  "instances": [
    {"type": "c6g.xlarge", "count": 2, "monthly_cost_per_unit": 200}
  ]
}
EOF

    # Create evil corpus
    cat << 'EOF' > /opt/verifier/evil/evil1.json
{
  "app_name": "api-service",
  "instances": [
    {"type": "t3.medium", "count": 4, "monthly_cost_per_unit": 30}
  ]
}
EOF

    cat << 'EOF' > /opt/verifier/evil/evil2.json
{
  "app_name": "db-service",
  "instances": [
    {"type": "m6g.4xlarge", "count": 4, "monthly_cost_per_unit": 400}
  ]
}
EOF

    cat << 'EOF' > /opt/verifier/evil/evil3.json
{
  "app_name": "cache-service",
  "instances": [
    {"type": "t4g.micro", "count": 1, "monthly_cost_per_unit": 10},
    {"type": "r5.large", "count": 1, "monthly_cost_per_unit": 150}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
