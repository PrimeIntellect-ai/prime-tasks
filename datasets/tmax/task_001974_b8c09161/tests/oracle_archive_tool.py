import sys
import json
import hashlib

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    with open('/app/archival_config.json', 'r') as f:
        config = json.load(f)

    with open(in_file, 'rb') as f:
        data = f.read()

    # Calculate hash of original data
    h = hashlib.new(config['hash_algorithm'])
    h.update(data)
    digest = h.hexdigest()

    # Transform: XOR with 0x5C
    transformed = bytearray([b ^ 0x5C for b in data])

    # Append manifest
    footer = f"{config['footer_prefix']}{digest}{config['footer_suffix']}".encode('utf-8')
    transformed.extend(footer)

    with open(out_file, 'wb') as f:
        f.write(transformed)

if __name__ == '__main__':
    main()
