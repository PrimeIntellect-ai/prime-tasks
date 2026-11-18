#!/usr/bin/env python3
import sys
import urllib.parse
import re

def validate(allowed_domain, url):
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return "INVALID"

    path_lower = parsed.path.lower()
    if '../' in path_lower or '%2e%2e/' in path_lower:
        return "INVALID"

    if url.startswith('//'):
        return "INVALID"

    if url.startswith('/'):
        return f"SAFE: {url}"

    if parsed.scheme != 'https':
        return "INVALID"

    host = parsed.hostname
    if not host:
        return "INVALID"

    if host == allowed_domain or host.endswith('.' + allowed_domain):
        return f"SAFE: {url}"

    return "INVALID"

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("INVALID")
        sys.exit(1)

    res = validate(sys.argv[1], sys.argv[2])
    print(res)
