#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget
pip3 install pytest numpy scipy

mkdir -p /app
cd /app
wget https://files.pythonhosted.org/packages/source/f/fisher/fisher-0.1.9.tar.gz
tar -xzf fisher-0.1.9.tar.gz
rm fisher-0.1.9.tar.gz

# Modify setup.py to include the invalid flag
cd fisher-0.1.9
sed -i "s/Extension(/Extension(extra_compile_args=['-O99'], /g" setup.py

# Create the oracle script
cat << 'EOF' > /app/oracle_summarize.py
import sys
import json
import numpy as np
import scipy.stats as st
import fisher

def main():
    csv_path = sys.argv[1]
    data = np.genfromtxt(csv_path, delimiter=',', skip_header=1)

    cat1 = data[:, 0]
    cat2 = data[:, 1]

    c00 = np.sum((cat1 == 0) & (cat2 == 0))
    c01 = np.sum((cat1 == 0) & (cat2 == 1))
    c10 = np.sum((cat1 == 1) & (cat2 == 0))
    c11 = np.sum((cat1 == 1) & (cat2 == 1))

    pval = fisher.pvalue(int(c00), int(c01), int(c10), int(c11)).two_tail

    vals = data[:, 2:5]
    vals_centered = vals - np.mean(vals, axis=0)
    U, S, Vt = np.linalg.svd(vals_centered, full_matrices=False)
    pc1 = Vt[0, :]
    if pc1[0] < 0:
        pc1 = -pc1

    val1 = data[:, 2]
    mean_val1 = np.mean(val1)
    sem_val1 = st.sem(val1, ddof=1)
    ci_lower, ci_upper = st.t.interval(0.95, df=len(val1)-1, loc=mean_val1, scale=sem_val1)

    result = {
        "fisher_p": round(float(pval), 4),
        "pc1": [round(float(x), 4) for x in pc1],
        "val1_ci": [round(float(ci_lower), 4), round(float(ci_upper), 4)]
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
EOF

# Install fisher for the oracle to work? Wait, the oracle needs fisher installed to run, but the task is to fix it.
# Actually, the oracle is run by the verifier AFTER the agent has fixed and installed fisher.
# Or maybe the oracle needs a working fisher. If the verifier runs the oracle, it will use the environment's fisher.
# Wait, if the agent installs it, it will be available.
# We don't need to install it for the oracle during %post because the agent will install it.

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
