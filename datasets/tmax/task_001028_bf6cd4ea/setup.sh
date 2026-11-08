#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest aiohttp

    # Create vendored proxy package
    mkdir -p /app/cloud-proxy-0.1.0/cloud_proxy

    cat << 'EOF' > /app/cloud-proxy-0.1.0/setup.py
from setuptools import setup, find_packages

setup(
    name="cloud-proxy",
    version="0.1.0",
    packages=find_packages(),
    install_requires=["aiohttp"],
)
EOF

    cat << 'EOF' > /app/cloud-proxy-0.1.0/cloud_proxy/__init__.py
EOF

    cat << 'EOF' > /app/cloud-proxy-0.1.0/cloud_proxy/server.py
from aiohttp import web

async def handle_request(request):
    if request.method == "POST": return web.Response(status=403, text="POST forbidden")
    return web.Response(status=200, text="OK")

app = web.Application()
app.router.add_route('*', '/{tail:.*}', handle_request)

if __name__ == '__main__':
    web.run_app(app, port=8080)
EOF

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/migrator_router.py
#!/usr/bin/env python3
import sys
from urllib.parse import urlparse, parse_qsl, urlunparse, urlencode

def route(uri):
    parsed = urlparse(uri)
    path = parsed.path

    if uri.startswith('/static/'):
        return '/mnt/legacy_assets/' + uri[8:]

    if '.php' in path:
        if parsed.query:
            query_params = parse_qsl(parsed.query, keep_blank_values=True)
            query_params.sort(key=lambda x: x[0])
            sorted_query = urlencode(query_params)
            new_parsed = parsed._replace(query=sorted_query)
            return 'http://lamp-legacy:80' + urlunparse(new_parsed)
        return 'http://lamp-legacy:80' + uri

    if uri.startswith('/api/v1/'):
        return 'http://legacy-svc:8080' + uri

    if uri.startswith('/api/v2/'):
        return 'http://new-svc:9000' + uri

    return 'http://default-router:8080' + uri

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(route(sys.argv[1]))
EOF
    chmod +x /opt/oracle/migrator_router.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
