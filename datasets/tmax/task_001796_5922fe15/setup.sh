#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import pandas as pd
import numpy as np

np.random.seed(10)
n = 100
df_exp = pd.DataFrame({
    'user_id': range(1, n+1),
    'group': np.random.choice(['A', 'B'], n),
    'conversion': np.random.choice([0, 1], n),
    'session_duration': np.random.normal(15, 5, n)
})
df_exp.to_csv('/home/user/experiments.csv', index=False)

feedback_texts = ["fast checkout", "slow process", "great UI", "could be better", "loved the fast checkout process", "terrible experience", "will use again", "support was helpful", "fast but buggy", "checkout was too slow"]
df_feed = pd.DataFrame({
    'user_id': range(1, n+1),
    'feedback_text': np.random.choice(feedback_texts, n)
})

# Ensure at least one distinct target for Group B conversion
target_users = df_exp[(df_exp['group'] == 'B') & (df_exp['conversion'] == 1)]['user_id'].tolist()
if len(target_users) > 0:
    target_user = target_users[2] if len(target_users) > 2 else target_users[0]
    df_feed.loc[df_feed['user_id'] == target_user, 'feedback_text'] = "the fast checkout was amazing"

df_feed.to_csv('/home/user/feedback.csv', index=False)

with open('/home/user/plot.py', 'w') as f:
    f.write("""import matplotlib.pyplot as plt
import numpy as np

def generate_plot():
    data = np.random.normal(0, 1, 1000)
    fig = plt.figure()
    plt.hist(data, bins=30)
    plt.show() # This clears the figure in some headless environments before saving
    plt.savefig('/home/user/bootstrap_plot.png')

if __name__ == '__main__':
    generate_plot()
""")
EOF

    python3 /tmp/setup_task.py

    chmod -R 777 /home/user
