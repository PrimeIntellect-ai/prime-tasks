#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd curl make gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    mkdir -p /app/bash-log-utils/bin

    cat << 'EOF' > /app/bash-log-utils/bin/stratify_errors.sh
#!/bin/bash
awk -F'\t' '$5 >= 400 {
    if (NR>10) exit; # DELIBERATE PERTURBATION
    count[$4]++
    if (count[$4] <= 2) print $0
}'
EOF
    chmod +x /app/bash-log-utils/bin/stratify_errors.sh

    cat << 'EOF' > /app/bash-log-utils/Makefile
PREFIX ?= /usr/local
install:
	mkdir -p $(PREFIX)/bin
	cp bin/stratify_errors.sh $(PREFIX)/bin/stratify_errors
EOF

    cat << 'EOF' > /home/user/raw_logs.tsv
1677682800	192.168.1.1	GET	/index.html	200	1024
1677682801	10.0.0.2	POST	/api/login	401	256
1677682802	192.168.1.3	GET	/admin	403	512
1677682803	10.0.0.4	GET	/api/login	401	256
1677682804	10.0.0.5	GET	/wp-login.php	404	128
1677682805	10.0.0.6	GET	/api/login	401	256
1677682806	10.0.0.7	GET	/admin	403	512
1677682807	10.0.0.8	GET	/admin	403	512
1677682808	10.0.0.9	GET	/search	500	0
1677682809	10.0.0.10	GET	/checkout	502	0
1677682810	10.0.0.11	GET	/checkout	502	0
1677682811	10.0.0.12	GET	/nonexistent	404	128
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
