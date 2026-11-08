#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-setuptools
    pip3 install pytest

    # Create the vendored package directory
    mkdir -p /app/text-pipeline-server-1.0/text_pipeline

    # Create setup.py
    cat << 'EOF' > /app/text-pipeline-server-1.0/setup.py
from setuptools import setup, find_packages

setup(
    name='text-pipeline-server',
    version='1.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'text-pipeline-server=text_pipeline.cli:main',
        ],
    },
)
EOF

    # Create __init__.py
    touch /app/text-pipeline-server-1.0/text_pipeline/__init__.py

    # Create parser.py with the flawed regex
    cat << 'EOF' > /app/text-pipeline-server-1.0/text_pipeline/parser.py
import re

def validate_batch_id(batch_id: str) -> bool:
    return bool(re.match(r'^batch-[a-z]+-\d+$', batch_id))
EOF

    # Create cli.py
    cat << 'EOF' > /app/text-pipeline-server-1.0/text_pipeline/cli.py
import argparse
import sys
from .server import run_server

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--handler', required=True)
    args = parser.parse_args()

    try:
        module_path, func_name = args.handler.split(':')
    except ValueError:
        print("Handler must be in format path/to/file.py:function_name")
        sys.exit(1)

    run_server(args.host, args.port, module_path, func_name)
EOF

    # Create server.py
    cat << 'EOF' > /app/text-pipeline-server-1.0/text_pipeline/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import importlib.util
import sys
from .parser import validate_batch_id

def load_handler(module_path, func_name):
    spec = importlib.util.spec_from_file_location("dynamic_handler", module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["dynamic_handler"] = module
    spec.loader.exec_module(module)
    return getattr(module, func_name)

def run_server(host, port, module_path, func_name):
    handler_func = load_handler(module_path, func_name)

    class RequestHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/ingest':
                self.send_response(404)
                self.end_headers()
                return

            batch_id = self.headers.get('X-Batch-ID', '')
            if not validate_batch_id(batch_id):
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad Request: Invalid X-Batch-ID")
                return

            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')

            try:
                result = handler_func(post_data)
                response_data = json.dumps(result).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(response_data)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode('utf-8'))

    server_address = (host, port)
    httpd = HTTPServer(server_address, RequestHandler)
    httpd.serve_forever()
EOF

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
