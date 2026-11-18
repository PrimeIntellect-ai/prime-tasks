#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,name,status
1,Alice,active
2,Bob,inactive
3,Charlie,active
4,David,active
5,Eve,inactive
EOF

    cat << 'EOF' > /home/user/purchases.csv
purchase_id,user_id,amount
101,1,50
102,1,75
103,2,100
104,3,20
105,4,200
106,4,10
107,1,10
108,5,500
EOF

    cat << 'EOF' > /home/user/report.sh
#!/bin/bash
# Convert CSV to JSON
python3 -c "import csv, json; print(json.dumps([r for r in csv.DictReader(open('/home/user/users.csv'))]))" > /home/user/users.json
python3 -c "import csv, json; print(json.dumps([r for r in csv.DictReader(open('/home/user/purchases.csv'))]))" > /home/user/purchases.json

# Buggy jq pipeline
jq -n --slurpfile u /home/user/users.json --slurpfile p /home/user/purchases.json '
  [
    $u[0][] as $user |
    $p[0][] as $purchase |
    {
      name: $user.name,
      total_spent: ($purchase.amount | tonumber)
    }
  ] | group_by(.name) | map({name: .[0].name, total_spent: map(.total_spent) | add}) | sort_by(.name)
' > /home/user/summary.json
EOF

    chmod +x /home/user/report.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
