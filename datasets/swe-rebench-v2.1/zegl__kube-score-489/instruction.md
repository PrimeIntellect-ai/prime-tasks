kube-score/ignore ignored at pod level inside a statefulset
I am deploying Trivy with their Helm chart, so Trivy is deployed as a statefulset.

The Trivy chart only allows to add annotations at the pod level (i.e. not at the statefulset level) so I added the `kube-score/ignore`  annotation at the pod level:
```
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: trivy
  namespace: trivy-staging
spec:
  podManagementPolicy: Parallel
  replicas: 3
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app.kubernetes.io/instance: trivy
      app.kubernetes.io/name: trivy
  serviceName: trivy
  template:
    metadata:
      annotations:
        kube-score/ignore: container-image-tag,pod-probes
      labels:
        app.kubernetes.io/instance: trivy
        app.kubernetes.io/name: trivy
    spec:
      automountServiceAccountToken: false
      containers:
      - args:
        - server
        envFrom:
        - configMapRef:
            name: trivy
        - secretRef:
            name: trivy
        image: aquasec/trivy:latest
        imagePullPolicy: Always
        livenessProbe:
          failureThreshold: 10
          httpGet:
            path: /healthz
            port: trivy-http
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        name: main
        ports:
        - containerPort: 4954
          name: trivy-http
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /healthz
            port: trivy-http
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        resources:
          limits:
            cpu: "1"
            ephemeral-storage: 128Mi
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 512Mi
        securityContext:
          privileged: false
          readOnlyRootFilesystem: true
          runAsGroup: 65534
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /tmp
          name: tmp-data
        - mountPath: /home/scanner/.cache
          name: data
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext:
        fsGroup: 65534
        runAsNonRoot: true
        runAsUser: 65534
      serviceAccount: trivy
      serviceAccountName: trivy
      terminationGracePeriodSeconds: 30
      volumes:
      - emptyDir: {}
        name: tmp-data
  updateStrategy:
    rollingUpdate:
      partition: 0
    type: RollingUpdate
  volumeClaimTemplates:
  - apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      creationTimestamp: null
      name: data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
      volumeMode: Filesystem
    status:
      phase: Pending
```

But then kube-score does not ignore the `container-image-tag` and `pod-probes` checks:
```
apps/v1/StatefulSet trivy in trivy-staging                                    💥
    [WARNING] Container Ephemeral Storage Request and Limit
        · main -> Ephemeral Storage request is not set
            Resource requests are recommended to make sure the application can
            start and run without crashing. Set
            resource.requests.ephemeral-storage
    [CRITICAL] Pod NetworkPolicy
        · The pod does not have a matching NetworkPolicy
            Create a NetworkPolicy that targets this pod to control who/what
            can communicate with this pod. Note, this feature needs to be
            supported by the CNI implementation used in the Kubernetes cluster
            to have an effect.
    [CRITICAL] Container Image Tag
        · main -> Image with latest tag
            Using a fixed tag is recommended to avoid accidental upgrades
    [CRITICAL] Pod Probes
        · Container has the same readiness and liveness probe
            Using the same probe for liveness and readiness is very likely
            dangerous. Generally it's better to avoid the livenessProbe than
            re-using the readinessProbe.
            More information: https://github.com/zegl/kube-score/blob/master/README_PROBES.md
    [WARNING] StatefulSet has host PodAntiAffinity
        · StatefulSet does not have a host podAntiAffinity set
            It's recommended to set a podAntiAffinity that stops multiple pods
            from a statefulset from being scheduled on the same node. This
            increases availability in case the node becomes unavailable.
    [CRITICAL] StatefulSet has ServiceName
        · StatefulSet does not have a valid serviceName
            StatefulSets currently require a Headless Service to be responsible
            for the network identity of the Pods. You are responsible for
            creating this Service.
            https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#limitations
    [CRITICAL] StatefulSet has PodDisruptionBudget
        · No matching PodDisruptionBudget was found
            It's recommended to define a PodDisruptionBudget to avoid
            unexpected downtime during Kubernetes maintenance operations, such
            as when draining a node.

```

### Additional contract requirements

When ignore-annotation processing is enabled, a StatefulSet pod-template `kube-score/ignore` annotation suppresses the checks it names and leaves checks it does not name active. When ignore-annotation processing is disabled, the pod-template annotation does not suppress checks.
