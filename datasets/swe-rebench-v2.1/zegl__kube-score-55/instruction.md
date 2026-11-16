Failing when use ExternalName in Service
```
---
apiVersion: v1
kind: Service
metadata:
  name: wp-site
  namespace: site
spec:
  externalName: wp.example.com
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  type: ExternalName
```

**Output:**

```
v1/Service wp-site in site
    [OK] Stable version
    [CRITICAL] Service Targets Pod
        * The services selector does not match any pods
```

### Additional contract requirements

An ExternalName Service must not fail the “Service Targets Pod” check because it has no pod selector.
