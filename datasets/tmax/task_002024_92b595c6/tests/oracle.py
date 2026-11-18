import sys
import re

def process():
    for line in sys.stdin:
        if '8443' in line:
            continue

        line = re.sub(r'--password \S+', '--password REDACTED', line)
        line = re.sub(r'Cookie: \S+', 'Cookie: REDACTED', line)
        line = re.sub(r'Authorization: Bearer \S+', 'Authorization: Bearer REDACTED', line)

        if 'telemetry.internal.corp' in line:
            line = line.rstrip('\n') + ' [TRUSTED]\n'

        sys.stdout.write(line)

if __name__ == '__main__':
    process()
