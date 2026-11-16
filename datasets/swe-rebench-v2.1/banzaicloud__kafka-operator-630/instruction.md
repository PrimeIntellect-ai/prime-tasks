KafkaCluster name is not propagated to the podAntiAffinity rule
**Describe the bug**
KafkaCluster name is not propagated to the podAntiAffinity rule

**Steps to reproduce the issue:**
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: kafka
          kafka_cr: ''
      topologyKey: kubernetes.io/hostname

**Expected behavior**
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: kafka
          kafka_cr: **KafkaClusterName**
      topologyKey: kubernetes.io/hostname

**Additional context**
Report by @amuraru
Via https://community-banzaicloud.slack.com/archives/CK75ATB29/p1623925465032600
