#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest dpkt scapy

    mkdir -p /app/data
    mkdir -p /app/vendor/pcap-processor/tests

    # Generate the pcap file with 10000 TCP and 5000 UDP packets
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import wrpcap, Ether, IP, TCP, UDP

tcp_pkts = [Ether()/IP()/TCP() for _ in range(10000)]
udp_pkts = [Ether()/IP()/UDP() for _ in range(5000)]
wrpcap('/app/data/test.pcap', tcp_pkts + udp_pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    # Create Makefile
    cat << 'EOF' > /app/vendor/pcap-processor/Makefile
test:
	PYTHONPATH=/wrong/path python3 -m unittest discover tests/
EOF

    # Create processor.py
    cat << 'EOF' > /app/vendor/pcap-processor/processor.py
import dpkt
import concurrent.futures

stats = {'tcp_count': 0, 'udp_count': 0}

def process_packet(buf):
    global stats
    eth = dpkt.ethernet.Ethernet(buf)
    if not isinstance(eth.data, dpkt.ip.IP): return
    ip = eth.data
    if isinstance(ip.data, dpkt.tcp.TCP):
        v = stats['tcp_count']
        stats['tcp_count'] = v + 1
    elif isinstance(ip.data, dpkt.udp.UDP):
        v = stats['udp_count']
        stats['udp_count'] = v + 1

def run_analysis(pcap_path):
    global stats
    stats = {'tcp_count': 0, 'udp_count': 0}
    with open(pcap_path, 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            for ts, buf in pcap:
                executor.submit(process_packet, buf)
    return stats
EOF

    # Create server.py
    cat << 'EOF' > /app/vendor/pcap-processor/server.py
import sys
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import socketserver

import processor

stats = processor.run_analysis(sys.argv[1])

class HTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/stats':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(stats).encode())
        else:
            self.send_response(404)
            self.end_headers()

class TCPHandler(socketserver.StreamRequestHandler):
    def handle(self):
        data = self.rfile.readline().strip()
        if not data: return
        try:
            query = json.loads(data).get('query')
            if query == 'tcp':
                resp = {'count': stats.get('tcp_count', 0)}
            elif query == 'udp':
                resp = {'count': stats.get('udp_count', 0)}
            else:
                resp = {'error': 'unknown query'}
            self.wfile.write((json.dumps(resp) + '\n').encode())
        except Exception:
            pass

def run_http():
    HTTPServer(('127.0.0.1', 8080), HTTPHandler).serve_forever()

def run_tcp():
    socketserver.TCPServer(('127.0.0.1', 8081), TCPHandler).serve_forever()

if __name__ == '__main__':
    threading.Thread(target=run_http, daemon=True).start()
    run_tcp()
EOF

    # Create empty test file so unittest discover finds something
    touch /app/vendor/pcap-processor/tests/__init__.py
    cat << 'EOF' > /app/vendor/pcap-processor/tests/test_processor.py
import unittest
import processor

class TestProcessor(unittest.TestCase):
    def test_dummy(self):
        self.assertTrue(True)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
