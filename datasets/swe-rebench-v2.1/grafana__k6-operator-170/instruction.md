k6.spec.separate also applies affinity to starter-pod
### Brief summary

Hi,

it seems that when separating runners to different nodes, the starter-pod is also been scheduled on its own node. Is this intended?

### k6-operator version or image

0.0.8

### K6 YAML

apiVersion: k6.io/v1alpha1
kind: K6
metadata:
  name: k6-test
spec:
  parallelism: 2
  separate: true


### Other environment details (if applicable)

_No response_

### Steps to reproduce the problem

Deploy k6 CRD with separate=true

### Expected behaviour

AntiAffinity should only affect runner-pods not initializer and starter

### Actual behaviour

AntiAffinity is applied to runner and starter pods
