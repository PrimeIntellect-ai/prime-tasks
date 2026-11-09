#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget curl
    pip3 install pytest

    mkdir -p /app/mongoose-7.11 /app/logs /app/templates

    # Download mongoose 7.11
    wget -qO /app/mongoose-7.11/mongoose.c https://raw.githubusercontent.com/cesanta/mongoose/7.11/mongoose.c
    wget -qO /app/mongoose-7.11/mongoose.h https://raw.githubusercontent.com/cesanta/mongoose/7.11/mongoose.h

    # Create Makefile
    cat << 'EOF' > /app/mongoose-7.11/Makefile
CFLAGS = -Werror -O2 -D_WIN32

all: mongoose.o

mongoose.o: mongoose.c
	$(CC) $(CFLAGS) -c mongoose.c -o mongoose.o

clean:
	rm -f mongoose.o
EOF

    # Create template without literal curly braces together to avoid Apptainer build variable errors
    OB="{"
    CB="}"
    cat << EOF > /app/templates/report.html.tmpl
<html><body><h1>Incident Report</h1><p>Peak Time: ${OB}${OB}PEAK_TIME${CB}${CB}</p><p>Errors: ${OB}${OB}ERROR_COUNT${CB}${CB}</p><p>Involved IPs: ${OB}${OB}SAMPLED_IPS${CB}${CB}</p></body></html>
EOF

    # Generate deterministic log file
    # Format: <UNIX_TIMESTAMP> <IP_ADDRESS> <HTTP_STATUS> <LATENCY_MS>
    cat << 'EOF' > /app/logs/microservice.log
1700000000 192.168.1.1 200 12
1700000010 192.168.1.2 200 15
1700000020 192.168.1.3 500 120
1700000030 192.168.1.4 502 110
1700000040 192.168.1.5 200 20
1700000060 10.0.0.1 500 100
1700000060 10.0.0.2 502 150
1700000060 10.0.0.3 503 200
1700000060 10.0.0.4 500 120
1700000060 10.0.0.1 500 100
1700000060 10.0.0.2 500 100
1700000060 10.0.0.3 500 100
1700000060 10.0.0.4 500 100
1700000060 10.0.0.1 500 100
1700000060 10.0.0.2 500 100
1700000060 10.0.0.3 500 100
1700000060 10.0.0.4 500 100
1700000060 10.0.0.1 500 100
1700000060 10.0.0.2 500 100
1700000060 10.0.0.3 500 100
1700000070 192.168.1.1 200 10
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
