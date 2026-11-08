#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.random.rand(1000)
y = 2 * x + 1 + np.random.randn(1000) * 0.5
df = pd.DataFrame({'id': range(1000), 'f1': x, 'f2': y})

# Inject missing values (NaNs)
df.loc[10:50, 'f1'] = np.nan
df.loc[800:850, 'f2'] = np.nan
df.loc[100:105, 'f1'] = ""

df.to_csv('dataset.csv', index=False, na_rep='NA')

# Calculate expected correlation
expected_corr = df[['f1', 'f2']].replace("", np.nan).dropna().astype(float).corr().loc['f1', 'f2']
with open('.expected_truth', 'w') as f:
    f.write(f"{expected_corr:.6f}")
EOF

    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > calc_corr.sh
#!/bin/bash
# Computes Pearson correlation between col 2 and 3
awk -F',' '
NR>1 {
    sum_x += $2; sum_y += $3;
    sum_x2 += $2*$2; sum_y2 += $3*$3;
    sum_xy += $2*$3;
    n++;
}
END {
    numerator = sum_xy - (sum_x * sum_y / n);
    denominator = sqrt((sum_x2 - (sum_x * sum_x / n)) * (sum_y2 - (sum_y * sum_y / n)));
    if (denominator == 0) print 0;
    else printf "%.6f\n", numerator / denominator;
}' $1
EOF
    chmod +x calc_corr.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
