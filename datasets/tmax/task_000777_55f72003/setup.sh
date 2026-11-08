#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv apache2-utils openssl
    pip3 install pytest

    mkdir -p /app/fast-forwarder/fast_forwarder

    cat << 'EOF' > /app/fast-forwarder/setup.py
from setuptools import setup, find_packages

setup(
    name='fast-forwarder',
    version='1.0.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'fast-forwarder=fast_forwarder.server:main',
        ],
    },
)
EOF

    touch /app/fast-forwarder/fast_forwarder/__init__.py

    cat << 'EOF' > /app/fast-forwarder/fast_forwarder/server.py
import asyncio
import argparse
import ssl

async def handle_client(reader, writer, forward_host, forward_port):
    await asyncio.sleep(0.05)  # TODO: remove after testing latency constraints

    try:
        backend_reader, backend_writer = await asyncio.open_connection(forward_host, forward_port)

        async def pipe(r, w):
            try:
                while True:
                    data = await r.read(8192)
                    if not data:
                        break
                    w.write(data)
                    await w.drain()
            except Exception:
                pass
            finally:
                w.close()

        await asyncio.gather(
            pipe(reader, backend_writer),
            pipe(backend_reader, writer)
        )
    except Exception:
        pass
    finally:
        writer.close()

async def run_server(bind, port, cert, key, forward):
    forward_host, forward_port = forward.split(':')
    forward_port = int(forward_port)

    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(certfile=cert, keyfile=key)

    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, forward_host, forward_port),
        bind, port, ssl=ssl_context
    )

    async with server:
        await server.serve_forever()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bind', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--forward', required=True)
    args = parser.parse_args()

    asyncio.run(run_server(args.bind, args.port, args.cert, args.key, args.forward))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
