#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq gawk bc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/customers.csv
customer_id,name,region
1,Alice,North
2,Bob,South
3,Charlie,North
4,Diana,East
5,Eve,West
6,Frank,East
EOF

cat << 'EOF' > /home/user/purchases.csv
purchase_id,customer_id,amount
101,1,50.00
102,2,75.50
103,1,20.00
104,3,100.00
105,4,200.00
106,2,24.50
107,6,50.00
EOF

cat << 'EOF' > /home/user/analyze.sh
#!/bin/bash
# Buggy script with implicit cross join
echo "{" > /home/user/region_summary.json
while IFS=, read -r cid name region; do
    if [ "$cid" == "customer_id" ]; then continue; fi
    total=0
    while IFS=, read -r pid pcid amount; do
        if [ "$pid" == "purchase_id" ]; then continue; fi
        # Missing proper condition, adding all amounts!
        total=$(echo "$total + $amount" | bc)
    done < /home/user/purchases.csv
    echo "\"$region\": $total," >> /home/user/region_summary.json
done < /home/user/customers.csv
echo "}" >> /home/user/region_summary.json
EOF

chmod +x /home/user/analyze.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
