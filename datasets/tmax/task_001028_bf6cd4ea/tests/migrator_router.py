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
