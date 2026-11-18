#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest fastapi uvicorn

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/data', exist_ok=True)

with open('/home/user/data/project.actlog', 'w') as f:
    f.write('''# Legacy Activity Log
# Generated automatically

BEGIN FrontendClient
ACTION update_deps
FILE package.json
ACTION lint
FILE src/components/Button.tsx
END

# Backend work
BEGIN PaymentGateway
ACTION refactor
FILE app/services/stripe.py
ACTION secure
FILE app/config/keys.py
ACTION test
FILE tests/integration/test_stripe.py
END

BEGIN DataPipeline
ACTION optimize
FILE scripts/etl.py
END
''')

with open('/home/user/large.actlog', 'w') as f:
    for i in range(5000):
        f.write(f'BEGIN Project_{i}\n')
        for j in range(5):
            f.write(f'ACTION action_{j}\n')
            f.write(f'FILE file_{i}_{j}.txt\n')
        f.write('END\n')
"

    chmod -R 777 /home/user
