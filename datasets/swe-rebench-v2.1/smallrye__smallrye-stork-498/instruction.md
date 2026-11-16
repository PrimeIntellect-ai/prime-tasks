Knative SD implementation doesn't get the correct service instance endpoint
From [this PR](https://github.com/quarkusio/quarkus/pull/30272)

The knative service discovery strategy is not working correctly. Given the quarkus-super-heroes project, when curl the rest-fights app on the /api/fights/randomfighters endpoint I would expect to see two random fighters, but I don’t. I see the fallback fighters
```
╰─ http https://rest-fights-eric-deandrea-dev.apps.sandbox-m2.ll9k.p1.openshiftapps.com/api/fights/randomfighters
HTTP/1.1 200 OK
cache-control: private
content-length: 314
content-type: application/json;charset=UTF-8
date: Mon, 06 Feb 2023 16:39:59 GMT
server: envoy
set-cookie: f876558f2b90f5b848dd878960dd0dc7=539d5cd9b01519008a395f7357457294; path=/; HttpOnly
x-envoy-upstream-service-time: 859

{
    "hero": {
        "level": 1,
        "name": "Fallback hero",
        "picture": "https://dummyimage.com/280x380/1e8fff/ffffff&text=Fallback+Hero",
        "powers": "Fallback hero powers"
    },
    "villain": {
        "level": 45,
        "name": "Fallback villain",
        "picture": "https://dummyimage.com/280x380/b22222/ffffff&text=Fallback+Villain",
        "powers": "Fallback villain powers"
    }
}
```
To reproduce:
using https://developers.redhat.com/developer-sandbox
https://github.com/edeandrea/quarkus-super-heroes/tree/fix-stork
Steps to deploy:
Make sure you’re using Java 17!
1 - oc apply -f https://raw.githubusercontent.com/edeandrea/quarkus-super-heroes/fix-stork/rest-villains/deploy/k8s/java17-knative.yml
2 - oc apply -f https://raw.githubusercontent.com/edeandrea/quarkus-super-heroes/fix-stork/rest-heroes/deploy/k8s/java17-knative.yml
3 - Clone https://github.com/edeandrea/quarkus-super-heroes and switch to the fix-stork branch
4 -
```
cd quarkus-super-heroes/rest-fights
./mvnw clean package -DskipTests \
  -Dquarkus.profile=knative-openshift-17 \
  -Dquarkus.container-image.registry=image-registry.openshift-image-registry.svc:5000 \
  -Dquarkus.container-image.group=$(oc project -q) \
  -Dquarkus.knative.labels.\"app.openshift.io/runtime\"=quarkus \
  -Dquarkus.knative.version=1.0 \
  -Dquarkus.kubernetes.deploy=true
```

### Additional contract requirements

- `io.smallrye.stork.api.ServiceInstance.getHost()` returns the plain host name taken from the Knative service URL, with the protocol scheme (for example `http://` or `https://`) removed.
- `io.smallrye.stork.api.ServiceInstance.getPort()` returns `-1` for a service instance discovered by the Knative service discovery.
- If the Knative service URL cannot be parsed, `getHost()` returns the original URL value.
