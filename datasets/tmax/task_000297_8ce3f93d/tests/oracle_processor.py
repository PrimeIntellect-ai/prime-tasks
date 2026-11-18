import sys
import hashlib

def main():
    raw_data = sys.stdin.buffer.read()
    text = raw_data.decode('utf-8', errors='replace')

    lines = text.split('\n')
    # handle the case where split creates an extra empty line if the file ends with \n
    # but we should process line by line as splitlines(True) keeps the \n

    sha1 = hashlib.sha1(raw_data).hexdigest()

    # We will iterate line by line, preserving the original line endings
    import io
    reader = io.StringIO(text)

    for line in reader:
        if 'TODO' in line:
            continue
        if line.startswith('CMD: '):
            sys.stdout.write(line.upper())
        else:
            sys.stdout.write(line)

    # Add newline if the last line didn't have one, before printing manifest? 
    # The rule says: "After all lines are processed, output a final line exactly formatted as..."
    # Let's ensure MANIFEST is on its own line.
    if text and not text.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.write(f"MANIFEST: {sha1}\n")

if __name__ == '__main__':
    main()
