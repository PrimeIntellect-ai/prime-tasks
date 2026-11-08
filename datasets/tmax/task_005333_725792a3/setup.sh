#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyinstaller hypothesis

    # Create the oracle in Python and compile it to a binary to simulate the Rust binary
    cat << 'EOF' > /tmp/oracle.py
import sys
import urllib.parse
import posixpath

def main():
    if len(sys.argv) != 2:
        print("ERROR:INVALID_URL")
        sys.exit(1)

    url_str = sys.argv[1]
    try:
        # Basic validation
        parsed = urllib.parse.urlparse(url_str)
        if not parsed.scheme or not parsed.netloc:
            print("ERROR:INVALID_URL")
            sys.exit(1)

        # Normalize path
        path = posixpath.normpath(parsed.path)

        # Percent decode path
        path = urllib.parse.unquote(path, errors='replace')

        # Split path into components
        components = [c for c in path.split('/') if c]

        # Extract and sort query parameters
        query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True, errors='replace')
        query.sort(key=lambda x: x[0])

        # Format output
        out = f"PATH:[{','.join(components)}]"
        if query:
            q_str = '&'.join(f"{k}={v}" for k, v in query)
            out += f" QUERY:{q_str}"

        print(out)
        sys.exit(0)
    except Exception:
        print("ERROR:INVALID_URL")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

    # Compile to a standalone binary
    pyinstaller --onefile /tmp/oracle.py

    # Place it in the expected location
    mkdir -p /app
    cp dist/oracle /app/legacy_router
    chmod +x /app/legacy_router

    # Clean up build files
    rm -rf build dist /tmp/oracle.py oracle.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
