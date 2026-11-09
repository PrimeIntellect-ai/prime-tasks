#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(42)
df = pd.DataFrame(np.random.randn(1000, 3) * 5 + 2, columns=['f1', 'f2', 'f3'])
df.to_csv('/home/user/raw_data.csv', index=False)
"

    chmod -R 777 /home/user
