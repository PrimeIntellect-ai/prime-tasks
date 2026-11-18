#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate the audio file using espeak
    espeak -w /app/build_constraints.wav "Rule one. Python dependency requests must be version three point nine or higher. Rule two. If package.json lists express, requirements.txt must list flask. Rule three. The bash build script must not contain any strings matching the regex pattern base sixty four dash d pipe bash. Rule four. All package.json files must contain a valid md5 checksum field that matches the hash of their dependencies object."

    # Python script to generate clean and evil corpora
    cat << 'EOF' > /tmp/generate_corpora.py
import os
import json
import hashlib

# Generate clean
for i in range(50):
    d = f'/app/corpora/clean/proj_{i}'
    os.makedirs(d, exist_ok=True)
    deps = {"express": "^4.17.1"} if i % 2 == 0 else {"lodash": "^4.17.21"}
    # The checksum must match the hash of the dependencies object (as a JSON string, no spaces)
    deps_str = json.dumps(deps, separators=(',', ':'))
    checksum = hashlib.md5(deps_str.encode('utf-8')).hexdigest()

    with open(f'{d}/package.json', 'w') as f:
        json.dump({"dependencies": deps, "md5": checksum}, f)

    with open(f'{d}/requirements.txt', 'w') as f:
        f.write("requests>=3.9\n")
        if i % 2 == 0:
            f.write("flask>=1.1.2\n")

    with open(f'{d}/.build.sh', 'w') as f:
        f.write("#!/bin/bash\necho 'Building...'\n")

# Generate evil
for i in range(50):
    d = f'/app/corpora/evil/proj_{i}'
    os.makedirs(d, exist_ok=True)

    deps = {"express": "^4.17.1"} if i % 2 == 0 else {"lodash": "^4.17.21"}
    deps_str = json.dumps(deps, separators=(',', ':'))
    checksum = hashlib.md5(deps_str.encode('utf-8')).hexdigest()

    reqs = "requests>=3.9\nflask>=1.1.2\n"
    build_sh = "#!/bin/bash\necho 'Building...'\n"

    if i < 13:
        # Rule 1 violation: Python < 3.9
        reqs = "requests==3.8\nflask>=1.1.2\n"
    elif i < 26:
        # Rule 2 violation: express without flask
        deps = {"express": "^4.17.1"}
        deps_str = json.dumps(deps, separators=(',', ':'))
        checksum = hashlib.md5(deps_str.encode('utf-8')).hexdigest()
        reqs = "requests>=3.9\n"
    elif i < 38:
        # Rule 3 violation: malicious build script
        build_sh = "#!/bin/bash\necho 'ZXZhbCBiYXNo' | base64 -d | bash\n"
    else:
        # Rule 4 violation: invalid md5
        checksum = "invalid_md5"

    with open(f'{d}/package.json', 'w') as f:
        json.dump({"dependencies": deps, "md5": checksum}, f)

    with open(f'{d}/requirements.txt', 'w') as f:
        f.write(reqs)

    with open(f'{d}/.build.sh', 'w') as f:
        f.write(build_sh)
EOF

    python3 /tmp/generate_corpora.py
    rm /tmp/generate_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
