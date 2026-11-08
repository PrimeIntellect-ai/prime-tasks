#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick rustc cargo python3-yaml
pip3 install pytest pyyaml

mkdir -p /app
# Generate the topology rules image
convert -size 800x400 xc:white -pointsize 18 -fill black \
-draw "text 20,50 'K8S TOPOLOGY RULES:'" \
-draw "text 20,100 '1. All Deployments in namespace \'backend\' must have exactly 5 replicas.'" \
-draw "text 20,150 '2. All Services must have a label \'network-tier: secure\'.'" \
-draw "text 20,200 '3. Any NetworkPolicy must include an ingress CIDR rule for \'10.0.0.0/8\'.'" \
/app/topology_rules.png

mkdir -p /home/user/input_manifests
mkdir -p /home/user/output_manifests

# Generate 50 input manifests
python3 -c '
import yaml
import random
import os

kinds = ["Deployment", "Service", "NetworkPolicy"]
namespaces = ["default", "backend", "frontend"]

for i in range(50):
    kind = random.choice(kinds)
    ns = random.choice(namespaces)
    doc = {
        "apiVersion": "v1",
        "kind": kind,
        "metadata": {
            "name": f"resource-{i}",
            "namespace": ns,
            "labels": {"app": f"app-{i}"}
        }
    }
    if kind == "Deployment":
        doc["apiVersion"] = "apps/v1"
        doc["spec"] = {"replicas": random.choice([1, 2, 3, 5]), "template": {"spec": {"containers": [{"name": "c", "image": "nginx"}]}}}
    elif kind == "Service":
        doc["spec"] = {"ports": [{"port": 80}]}
        if random.choice([True, False]):
            doc["metadata"]["labels"]["network-tier"] = "insecure"
    elif kind == "NetworkPolicy":
        doc["apiVersion"] = "networking.k8s.io/v1"
        doc["spec"] = {"podSelector": {}, "ingress": [{"from": [{"ipBlock": {"cidr": "192.168.0.0/16"}}]}]}

    with open(f"/home/user/input_manifests/resource-{i}.yaml", "w") as f:
        yaml.dump(doc, f)
'

# Create evaluator
cat << 'EOF' > /home/user/evaluate_manifests.py
import sys
import os
import yaml

def evaluate():
    input_dir = "/home/user/input_manifests"
    output_dir = "/home/user/output_manifests"

    if not os.path.exists(output_dir):
        print(0.0)
        return

    in_files = set(os.listdir(input_dir))
    out_files = set(os.listdir(output_dir))

    if not in_files:
        print(0.0)
        return

    correct = 0
    total = len(in_files)

    for f in in_files:
        if f not in out_files:
            continue
        try:
            with open(os.path.join(output_dir, f)) as f_in:
                doc = yaml.safe_load(f_in)

            if not doc:
                continue

            kind = doc.get("kind")
            ns = doc.get("metadata", {}).get("namespace", "default")

            ok = True
            if kind == "Deployment" and ns == "backend":
                if doc.get("spec", {}).get("replicas") != 5:
                    ok = False

            if kind == "Service":
                if doc.get("metadata", {}).get("labels", {}).get("network-tier") != "secure":
                    ok = False

            if kind == "NetworkPolicy":
                ingress = doc.get("spec", {}).get("ingress", [])
                has_cidr = False
                for rule in ingress:
                    for frm in rule.get("from", []):
                        if frm.get("ipBlock", {}).get("cidr") == "10.0.0.0/8":
                            has_cidr = True
                if not has_cidr:
                    ok = False

            if ok:
                correct += 1
        except:
            pass

    print(float(correct) / total)

if __name__ == "__main__":
    evaluate()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
