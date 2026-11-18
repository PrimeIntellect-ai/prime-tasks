#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scipy

useradd -m -s /bin/bash user || true

python3 -c "
import os
import random

os.makedirs('/home/user/data', exist_ok=True)
random.seed(42)

users = []
purchases = []
activity = []

for i in range(1, 1001):
    user_id = i
    age = random.randint(18, 70)
    users.append((user_id, age))

    if random.random() < 0.7:
        base_amount = age * 2.5
        noise = random.uniform(-20, 20)
        amount = round(max(5.0, base_amount + noise), 2)
        purchases.append((user_id, amount))

    if random.random() < 0.9:
        logins = random.randint(1, 100)
        activity.append((user_id, logins))

with open('/home/user/data/users.csv', 'w') as f:
    f.write('user_id,age\n')
    for u in users: f.write(f'{u[0]},{u[1]}\n')

with open('/home/user/data/purchases.csv', 'w') as f:
    f.write('user_id,purchase_amount\n')
    random.shuffle(purchases)
    for p in purchases: f.write(f'{p[0]},{p[1]}\n')

with open('/home/user/data/activity.csv', 'w') as f:
    f.write('user_id,login_count\n')
    random.shuffle(activity)
    for a in activity: f.write(f'{a[0]},{a[1]}\n')
"

chown -R user:user /home/user/data
chmod -R 777 /home/user
