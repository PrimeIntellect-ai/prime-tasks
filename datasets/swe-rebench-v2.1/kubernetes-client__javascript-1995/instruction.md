ListWatch initial list performance is slow
**Describe the bug**
When a list watch is created (or any other time `listWatch.resourceVersion === ''`), the ListWatch will attempt to bootstrap its list of objects. Insertion of items from the API Server's List response into `ListWatch.objects` is n^2, and can be very slow for very large quantities of objects (on the order of 100K).

In particular:
[HIDDEN]


** Client Version **
`1.0.0-rc6`

** Server Version **
`1.29.8` (Although I don't think this is relevant)

**To Reproduce**
I added a shim into cache.js in the @kubernetes/client-node package to keep track of how many times a object in cache was accessed via `findKubernetesObject`.
```javascript
function findKubernetesObject(objects, obj) {
    return objects.findIndex((elt) => {
        ++global.accesses;   // This is the only addition
        return isSameObject(elt, obj);
    });
}
```

_test.mjs_
```javascript
import * as k8s from '@kubernetes/client-node';

const apiUrl = '/apis/v1/namespaces/default/configmaps';

global.accesses = 0;

const kc = new k8s.KubeConfig(); kc.loadFromDefault();

const watch = new k8s.Watch(kc);
const client = kc.makeApiClient(k8s.CoreV1Api);

const lw = new k8s.ListWatch(
    apiUrl,
    watch,
    async () => {
        const x = await client.listNamespacedConfigMap({namespace: 'default'});
        console.log('fetched items', x.items.length);
        return x;
    },
    false
);

const start = performance.now();
await lw.start()
console.log('elapsed', performance.now() - start);
console.log('object accesses', accesses)
```

Test context
```shell
$ minikube start
...
$ seq 50000 | xargs -P 100 -I'{}' kubectl create cm cm-'{}'
...
$ node test.mjs
fetched items 50004
elapsed 12140.640042
object accesses 2500350012
```


**Expected behavior**
It seems reasonable that insertion is O(n) if possible.

** Example Code**
N/A

**Environment (please complete the following information):**
 - OS: Linux
 - NodeJS Version: 20
 - Cloud runtime: EKS + Minikube

### Additional contract requirements

- Bootstrapping the cache from an initial list of `n` objects must scale linearly with `n`; inserting the initial list must not degrade to quadratic (O(n²)) behavior.
- `ListWatch.list(namespace?)` returns an empty array when the requested namespace has no cached entries.
