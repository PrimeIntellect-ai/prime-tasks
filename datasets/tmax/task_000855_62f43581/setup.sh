#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scipy matplotlib

mkdir -p /home/user
cd /home/user

# Generate the CSV data
python3 -c "
import random
import csv

random.seed(123)
with open('/home/user/ab_test_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'variant', 'converted'])

    # Variant A: 1000 users, true conversion rate ~ 10%
    for i in range(1000):
        converted = 1 if random.random() < 0.10 else 0
        writer.writerow([f'u_{i}', 'A', converted])

    # Variant B: 1050 users, true conversion rate ~ 12.5%
    for i in range(1000, 2050):
        converted = 1 if random.random() < 0.125 else 0
        writer.writerow([f'u_{i}', 'B', converted])
"

# Create the broken python script
cat << 'EOF' > /home/user/analyze.py
import pandas as pd
import numpy as np
from scipy.stats import beta
import matplotlib
# Hint: you might need to change the backend here for headless environments!
import matplotlib.pyplot as plt

def main():
    # Load data
    df = pd.read_csv('/home/user/ab_test_data.csv')

    # TODO: Group by 'variant' to get total 'converted' (successes) and total rows (trials)
    # aggregated = ...

    # Hardcoded fallback just so the script runs initially, replace this!
    successes_A, trials_A = 10, 100
    successes_B, trials_B = 10, 100

    # Priors
    alpha_prior, beta_prior = 1, 1

    # Posteriors
    alpha_A = alpha_prior + successes_A
    beta_A = beta_prior + (trials_A - successes_A)
    alpha_B = alpha_prior + successes_B
    beta_B = beta_prior + (trials_B - successes_B)

    # Plotting
    x = np.linspace(0, 0.3, 500)
    y_A = beta.pdf(x, alpha_A, beta_A)
    y_B = beta.pdf(x, alpha_B, beta_B)

    plt.plot(x, y_A, label='Variant A')
    plt.plot(x, y_B, label='Variant B')
    plt.legend()
    plt.title('Posterior Distributions')

    # Bug: This creates a blank plot if not configured correctly or if show() clears the canvas before savefig
    plt.show()
    plt.savefig('/home/user/posterior_plot.png')

    # TODO: Calculate probability that Variant B is better than Variant A using Monte Carlo
    # Draw 1,000,000 samples for each.
    np.random.seed(42)
    # prob_B_better = ...

    # TODO: Write the probability (rounded to 4 decimal places) to /home/user/prob_B_better.txt

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
