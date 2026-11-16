`--env-from` is not shown in `service describe` and `revision describe`
When environment variables are specified with `--env-from` to add from a configmap or a secret, they are correcly inserted into the Knative Service but not shown when using `kn service describe` or `kn revision describe`. They should appear on the same level as regular environment variables.

Walkthrough:

```
$ kubectl create cm testconfig --from-literal=FOO1=BAR1 --from-literal=FOO2=BAR2
configmap/testconfig created

$ kn service create random --image rhuss/random:1.0 --env-from cm:testconfig
Creating service 'random' in namespace 'default':
  0.123s The Route is still working to reflect the latest desired specification.
  0.166s Configuration "random" is waiting for a Revision to become ready.
 12.151s ...
 12.337s Ingress has not yet been reconciled.
 12.626s Ready to serve.
Service 'random' created to latest revision 'random-rdlzd-1' is available at URL:
http://random.default.example.com

$ kubectl exec -it random-rdlzd-1-deployment-75799bf844-4hknx bash
Defaulting container name to user-container.
Use 'kubectl describe pod/random-rdlzd-1-deployment-75799bf844-4hknx -n default' to see all of the containers in this pod.
bash-5.0# env | grep FOO
FOO1=BAR1
FOO2=BAR2

$ kn service describe random --verbose
Name:         random
Namespace:    default
Annotations:  serving.knative.dev/creator=minikube-user
              serving.knative.dev/lastModifier=minikube-user
Age:          5m
URL:          http://random.default.example.com
Cluster:      http://random.default.svc.cluster.local
Revisions:
  100%  @latest (random-rdlzd-1) [1] (5m)
        Image:  rhuss/random:1.0 (pinned to 946b7c)
Conditions:
  OK TYPE                   AGE REASON
  ++ Ready                   5m
  ++ ConfigurationsReady     5m
  ++ RoutesReady             5m

$ kn revision describe random-rdlzd-1 --verbose
Name:                        random-rdlzd-1
Namespace:                   default
Labels:                      serving.knative.dev/configuration=random
                             serving.knative.dev/configurationGeneration=1
                             serving.knative.dev/route=random
                             serving.knative.dev/service=random
Annotations:                 client.knative.dev/user-image=rhuss/random:1.0
                             serving.knative.dev/creator=minikube-user
                             serving.knative.dev/lastPinned=1580285962
Age:                         5m
Image:                       rhuss/random:1.0 (pinned to 946b7c)
Service:                     random
  Configuration Generation:  1
  Latest Created:            true
  Latest Ready:              true
  Traffic:                   100%
Conditions:
  OK TYPE                  AGE REASON
  ++ Ready                  5m
  ++ ContainerHealthy       5m
  ++ ResourcesAvailable     5m
   I Active                46s NoTraffic (The target is not receiving traffic.)
```
