#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    python3 -c '
import os
import csv
import random

os.makedirs("/home/user/data", exist_ok=True)

users = []
for i in range(1, 11):
    users.append([i, random.choice(["18-25", "26-35", "36-50"]), random.choice(["North", "South", "East", "West"])])

orders = []
returns = []
order_id = 100
for u in users:
    uid = u[0]
    num_orders = random.randint(0, 3)
    for _ in range(num_orders):
        order_amount = round(random.uniform(20.0, 200.0), 2)
        days_active = random.randint(10, 100)
        orders.append([order_id, uid, order_amount, days_active])

        # 30% chance of return
        if random.random() < 0.3:
            return_amount = round(random.uniform(5.0, order_amount), 2)
            returns.append([order_id, return_amount])
        order_id += 1

with open("/home/user/data/users.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["user_id","age_group","region"])
    writer.writerows(users)

with open("/home/user/data/orders.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["order_id","user_id","order_amount","days_active"])
    writer.writerows(orders)

with open("/home/user/data/returns.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["order_id","return_amount"])
    writer.writerows(returns)
'

    chmod -R 777 /home/user
