import sys
import re

def main():
    if len(sys.argv) < 2:
        return
    log_line = sys.argv[1]
    match = re.match(r'^(\S+)\s+\S+\s+\S+\s+\[.*?\]\s+"(\S+)\s+(\S+)\s+.*?"\s+(\d+)\s+', log_line)
    if match:
        ip, method, path, status = match.groups()
        output = f"IP: {ip} | METHOD: {method} | PATH: {path} | STATUS: {status}"
        if int(status) >= 400:
            output += " | ERROR"
        print(output)

if __name__ == '__main__':
    main()
