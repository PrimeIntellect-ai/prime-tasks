#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

log_processor_code = '''import sys

def resolve_dependencies(job_id, dependencies):
    # Buggy DFS: Missing a 'visited' set to handle cycles
    stack = [job_id]
    resolved_count = 0
    while stack:
        current = stack.pop()
        resolved_count += 1
        if current in dependencies:
            for dep in dependencies[current]:
                stack.append(dep)
    return resolved_count

def process_logs(log_lines):
    dependencies = {}
    pending_jobs = set()

    for line in log_lines:
        line = line.strip()
        if not line: continue
        parts = line.split(',')
        job = parts[0]
        action = parts[1]

        if action == 'REQUIRES':
            dep = parts[2]
            if job not in dependencies:
                dependencies[job] = []
            dependencies[job].append(dep)
            pending_jobs.add(job)
            pending_jobs.add(dep)
        elif action == 'COMPLETED':
            if job in pending_jobs:
                # Trigger dependency resolution
                resolve_dependencies(job, dependencies)
                pending_jobs.remove(job)

if __name__ == '__main__':
    with open(sys.argv[1], 'r') as f:
        process_logs(f.readlines())
'''

with open('/home/user/log_processor.py', 'w') as f:
    f.write(log_processor_code)

production_logs = []
for i in range(1, 100):
    production_logs.append(f'JOB_{i},REQUIRES,JOB_{i+1}')
    if i % 5 == 0:
        production_logs.append(f'JOB_{i},COMPLETED')

# Insert the poison pill (circular dependency)
production_logs.append('JOB_900,REQUIRES,JOB_901')
production_logs.append('JOB_901,REQUIRES,JOB_900')
production_logs.append('JOB_900,COMPLETED')

for i in range(101, 200):
    production_logs.append(f'JOB_{i},REQUIRES,JOB_{i+1}')

with open('/home/user/production_logs.txt', 'w') as f:
    f.write('\n'.join(production_logs))
"

    chmod -R 777 /home/user
