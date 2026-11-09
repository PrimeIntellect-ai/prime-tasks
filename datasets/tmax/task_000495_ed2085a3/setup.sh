#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils grep gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl_data/tables

    cat << 'EOF' > /home/user/etl_data/tables/customers.csv
id,name,region_id,status
1,Alice,10,active
EOF

    cat << 'EOF' > /home/user/etl_data/tables/regions.csv
id,region_name
10,North
EOF

    cat << 'EOF' > /home/user/etl_data/tables/orders.csv
id,customers_id,total
100,1,250.00
EOF

    cat << 'EOF' > /home/user/etl_data/tables/order_items.csv
id,orders_id,products_id,quantity
1001,100,55,2
EOF

    cat << 'EOF' > /home/user/etl_data/tables/products.csv
id,name,price
55,Widget,125.00
EOF

    cat << 'EOF' > /home/user/etl_data/tables/payments.csv
id,orders_id,amount,method
5001,100,250.00,credit
EOF

    cat << 'EOF' > /home/user/etl_data/tables/shipments.csv
id,orders_id,status
8001,100,shipped
EOF

    cat << 'EOF' > /home/user/etl_data/query_plan.txt
Nested Loop  (cost=100.00..5000.00 rows=1000 width=150)
  Join Filter: (orders.customers_id = customers.id)
  ->  Seq Scan on "orders"  (cost=0.00..2500.00 rows=50000 width=40)
        Filter: (total > 100)
  ->  Index Scan using customers_pkey on "customers"  (cost=0.00..8.00 rows=1 width=30)
        Index Cond: (id = orders.customers_id)
  ->  Hash Join  (cost=50.00..2000.00 rows=1000 width=80)
        Hash Cond: (order_items.products_id = products.id)
        ->  Seq Scan on "order_items"  (cost=0.00..1000.00 rows=20000 width=20)
        ->  Hash  (cost=40.00..40.00 rows=500 width=60)
              ->  Seq Scan on "products"  (cost=0.00..40.00 rows=500 width=60)
EOF

    chown -R user:user /home/user/etl_data
    chmod -R 777 /home/user
