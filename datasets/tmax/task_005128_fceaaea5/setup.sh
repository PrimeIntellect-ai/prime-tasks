#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/access_graph.txt
/api/resource?asset=app_js&ts=100 /api/resource?asset=vendor_js 0.50
/api/resource?asset=vendor_js /api/resource?asset=lodash_js&min=1 0.80
/api/resource?asset=app_js /api/resource?asset=lodash_js 0.20
/api/resource?v=2&asset=style_css /api/resource?asset=font_woff 0.90
/api/resource?asset=index_html /api/resource?asset=app_js 1.00
/api/resource?asset=index_html /api/resource?asset=style_css 1.00
/api/resource?asset=vendor_js /api/resource?asset=core_js&debug=true 0.30
EOF

    cat << 'EOF' > /home/user/pipeline/expected_scores.csv
app_js,1.0000
core_js,0.4050
font_woff,0.9150
index_html,0.1500
lodash_js,1.0000
style_css,1.0000
vendor_js,0.5750
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
