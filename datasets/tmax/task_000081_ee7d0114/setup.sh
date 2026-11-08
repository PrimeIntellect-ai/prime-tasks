#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump gawk
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_8832
    cd /home/user/ticket_8832

    # Create the flawed Makefile (uses spaces instead of tabs)
    echo "all: run" > Makefile
    echo "" >> Makefile
    echo "run: process_pcap.sh calc_variance.awk traffic.pcap" >> Makefile
    echo "    ./process_pcap.sh traffic.pcap | awk -f calc_variance.awk > output.txt" >> Makefile
    echo "" >> Makefile
    echo "clean:" >> Makefile
    echo "    rm -f output.txt" >> Makefile

    # Create process_pcap.sh
    cat << 'EOF' > process_pcap.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <pcap_file>"
    exit 1
fi
# BUG: Needs to output only sequence numbers. The current awk is broken and tcpdump doesn't output absolute seq numbers without -S.
tcpdump -r "$1" -n tcp 2>/dev/null | awk '{print $9}' 
EOF
    chmod +x process_pcap.sh

    # Create calc_variance.awk (Naive, numerically unstable formula)
    cat << 'EOF' > calc_variance.awk
BEGIN {
    sum = 0;
    sumsq = 0;
    n = 0;
}
{
    # Ignore empty lines
    if ($1 != "") {
        # Strip commas or colons if present from bad extraction
        gsub(/[^0-9]/, "", $1);
        val = $1 + 0;
        sum += val;
        sumsq += (val * val);
        n++;
    }
}
END {
    if (n > 1) {
        mean = sum / n;
        variance = (sumsq / n) - (mean * mean);
        printf "%.2f\n", variance;
    } else {
        print "0.00";
    }
}
EOF

    # Generate the PCAP file with python using scapy
    cat << 'EOF' > generate_pcap.py
from scapy.all import wrpcap, Ether, IP, TCP
packets = []
base_seq = 1000000000
for i in range(1, 101):
    pkt = Ether(dst="00:11:22:33:44:55", src="55:44:33:22:11:00") / \
          IP(src="192.168.1.1", dst="192.168.1.2") / \
          TCP(sport=1234, dport=80, seq=base_seq + i, flags="A")
    packets.append(pkt)

wrpcap("traffic.pcap", packets)
EOF
    python3 generate_pcap.py
    rm generate_pcap.py

    chown -R user:user /home/user/ticket_8832
    chmod -R 777 /home/user
