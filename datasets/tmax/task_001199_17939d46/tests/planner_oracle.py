import sys
import re
pattern = re.compile(r"^DATA node=([a-zA-Z0-9]+) cpu=(\d+) mem=(\d+) disk=(\d+)$")
for line in sys.stdin:
    line = line.strip('\n')
    match = pattern.match(line)
    if match:
        node, cpu, mem, disk = match.groups()
        score = (int(cpu) * 2) + (int(mem) // 10) + (int(disk) * 5)
        if score > 500:
            print(f"ALERT {node} {score}")
        else:
            print(f"OK {node} {score}")
