#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jinja2

    mkdir -p /home/user/config_data/server_alpha
    mkdir -p /home/user/config_data/server_beta
    mkdir -p /home/user/config_data/server_gamma

    # server_alpha
    cat << 'EOF' > /home/user/config_data/server_alpha/config_2023-10-01.json
{"system": {"version": 1.0, "hostname": "alpha"}, "network": {"port": 8080, "timeout": 30}}
EOF
    cat << 'EOF' > /home/user/config_data/server_alpha/config_2023-10-02.json
{"system": {"version": 1.0, "hostname": "alpha"}, "network": {"port": 8085, "timeout": 30}}
EOF
    cat << 'EOF' > /home/user/config_data/server_alpha/config_2023-10-03.json
{"system": {"version": 2.0, "hostname": "alpha-prod"}, "network": {"port": 9000, "timeout": 60}, "new_key": "exists"}
EOF

    # server_beta
    cat << 'EOF' > /home/user/config_data/server_beta/config_2023-10-01.json
{"users": {"admin": true, "guest": false}, "max_conn": 100}
EOF
    cat << 'EOF' > /home/user/config_data/server_beta/config_2023-10-02.json
{"users": {"admin": true, "guest": false}, "max_conn": 100}
EOF
    cat << 'EOF' > /home/user/config_data/server_beta/config_2023-10-03.json
{"users": {"admin": true, "guest": true}, "max_conn": 100}
EOF

    # server_gamma
    cat << 'EOF' > /home/user/config_data/server_gamma/config_2023-10-01.json
{"cache": 500}
EOF
    cat << 'EOF' > /home/user/config_data/server_gamma/config_2023-10-02.json
{"cache": 600}
EOF
    cat << 'EOF' > /home/user/config_data/server_gamma/config_2023-10-03.json
{"cache": 700}
EOF

    # Template (avoiding literal double curly braces for Apptainer)
    cat << 'EOF' > /home/user/report_template.html
<html>
<body>
<h1>Audit Report</h1>
<ul>
{% for srv, data in servers.items() %}
    <li id="OB_OB srv CB_CB">OB_OB srv CB_CB: Anomalies=OB_OB data.total_anomalies CB_CB, AvgDrift=OB_OB data.average_drift CB_CB</li>
{% endfor %}
</ul>
</body>
</html>
EOF

    sed -i 's/OB_OB/{{/g' /home/user/report_template.html
    sed -i 's/CB_CB/}}/g' /home/user/report_template.html

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
