#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak zip gcc
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "The archive password is: flamingo orange telescope"

    python3 -c '
import os
import random
import string
import subprocess

os.makedirs("/app", exist_ok=True)

with open("/app/rotator.c", "w") as f:
    f.write("""#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    printf("Rotating credentials...\\n");
    printf("Token format: SEC-ROT-[A-Z0-9]{16}\\n");
    return 0;
}
""")

subprocess.run(["gcc", "-o", "/app/rotator_elf", "/app/rotator.c"], check=True)

num_lines = 2000
num_leaks = 50
leak_indices = set(random.sample(range(num_lines), num_leaks))

logs = []
truth = []

for i in range(num_lines):
    if i in leak_indices:
        token = "".join(random.choices(string.ascii_uppercase + string.digits, k=16))
        line = f"root {1000+i} 0.0 0.1 1234 567 ? Ss 12:00 0:00 ./rotator_elf --auth=SEC-ROT-{token}\n"
        truth_line = f"root {1000+i} 0.0 0.1 1234 567 ? Ss 12:00 0:00 ./rotator_elf --auth=[REDACTED]\n"
    else:
        line = f"user {1000+i} 0.0 0.1 1234 567 ? Ss 12:00 0:00 /bin/bash\n"
        truth_line = line
    logs.append(line)
    truth.append(truth_line)

with open("/app/process_logs.txt", "w") as f:
    f.writelines(logs)

with open("/app/truth_redacted_logs.txt", "w") as f:
    f.writelines(truth)

os.chdir("/app")
subprocess.run(["zip", "-P", "flamingo orange telescope", "evidence.zip", "rotator_elf", "process_logs.txt"], check=True)

os.remove("/app/rotator.c")
os.remove("/app/rotator_elf")
os.remove("/app/process_logs.txt")
'

    chmod 600 /app/truth_redacted_logs.txt
    chown root:root /app/truth_redacted_logs.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
