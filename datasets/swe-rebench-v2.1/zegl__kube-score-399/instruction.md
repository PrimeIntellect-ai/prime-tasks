podAntiAffinity throws error when topologyKey for zones are used
**Which version of kube-score are you using?**

kube-score version: 1.12.0, commit: 82810c42bb501443116bfb67dde81bc2f68fa318, built: 2021-08-28T20:47:35Z

Wrote a deployment with

```yaml
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                  - secret-app
              topologyKey: topology.kubernetes.io/zone
            weight: 60
 ```

Got told:

```sh
apps/v1/Deployment secret-app in secret-app                              🤔
    [WARNING] Deployment has host PodAntiAffinity
        · Deployment does not have a host podAntiAffinity set
            It's recommended to set a podAntiAffinity that stops multiple pods
            from a deployment from being scheduled on the same node. This
            increases availability in case the node becomes unavailable.
```


Though if I change the topologyKey to hostname it works..

```yaml
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                  - secret-app
              topologyKey: topology.kubernetes.io/hostname
            weight: 60
 ```

Commands used to invoke kubescore


```
kustomize build . | kube-score score --ignore-test container-image-pull-policy --ignore-test pod-networkpolicy --ignore-tes
t deployment-has-poddisruptionbudget -
```

### Additional contract requirements

- Required pod anti-affinity using `topology.kubernetes.io/region` must also be recognized as valid and must not produce a warning.
- A required pod anti-affinity term with `topologyKey: topology.kubernetes.io/what-is-this-key` must produce a warning.
