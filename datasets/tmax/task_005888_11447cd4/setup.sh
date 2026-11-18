#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/crash_memory.dump
\x00\x01\x02\x03garbagedatahereMOREGARBAGE\x11\x22PAYLOAD_START{15,82,19,44,91,102,7,33,49,11,99,250,111,88,200,10}PAYLOAD_END\x00\xFFsome_more_random_memory_strings\x00
EOF

cat << 'EOF' > /home/user/processor.py
import threading
import sys
import time

total_checksum = 0

def calc_hash(val):
    # BUG: Incorrect formula precedence
    return val + 0x5A * 13 % 256

def worker(numbers):
    global total_checksum
    for n in numbers:
        h = calc_hash(n)
        # BUG: Race condition
        temp = total_checksum
        time.sleep(0.001) # exaggerate race condition
        temp += h
        total_checksum = temp

def main():
    if len(sys.argv) < 2:
        print("Usage: python processor.py <comma_separated_numbers>")
        return

    payload = sys.argv[1]
    numbers = [int(x) for x in payload.split(',')]

    threads = []
    chunk_size = max(1, len(numbers) // 4)

    for i in range(4):
        # Slice the list into 4 parts
        start_idx = i * chunk_size
        end_idx = (i + 1) * chunk_size if i < 3 else len(numbers)
        chunk = numbers[start_idx:end_idx]

        t = threading.Thread(target=worker, args=(chunk,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    print(total_checksum)

if __name__ == "__main__":
    main()
EOF

chmod -R 777 /home/user
