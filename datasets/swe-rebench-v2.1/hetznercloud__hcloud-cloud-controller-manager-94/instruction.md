Loadbalancer service healthcheck for traefik
Hi,

i deployed traefik to my cluster and have service working for it:

```bash
traefik                                      ClusterIP      10.96.231.57   <none>                     8000/TCP,8080/TCP,4443/TCP,27017/TCP        32h
my-hetzner-loadbalancer   LoadBalancer   10.96.57.135   10.98.0.2,<hide external lb ip>   80:30862/TCP,8080:32150/TCP,443:32425/TCP   34h
whoami                                       ClusterIP      10.96.117.38   <none>                     80/TCP                                      24h
```

I cant get Loadbalancer work longer than durring "healthcheck". I I go to port 8080 as soon i start changes on my loadbalancer i get webpages and websocket to traefik dashboard is connected. It holds connection aslong as i let browser tab  open. I can also reach "whoami" container with HTTPS.

But after healthcheck is done it goes red on web page with status unhealthy. And after that i cant connect any of the services.

Can someone help we with that?

Same behaviour i have on other accounts and loadbalancers.

Here my output.

Here my description for LB Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-hetzner-loadbalancer
  labels:
    app.kubernetes.io/name: hetzner-loadbalancer
    app.kubernetes.io/instance: my-hetzner
  annotations:
    # https://pkg.go.dev/github.com/hetznercloud/hcloud-cloud-controller-manager/internal/annotation?tab=doc
    load-balancer.hetzner.cloud/name: <my-hetzner-loadbalancer-name>
    load-balancer.hetzner.cloud/location: nbg1
    load-balancer.hetzner.cloud/type: "lb11"
    load-balancer.hetzner.cloud/use-private-ip: "true"
    load-balancer.hetzner.cloud/uses-proxyprotocol: "true"
spec:
  externalTrafficPolicy: Cluster
  selector:
    app.kubernetes.io/instance: traefik
    app.kubernetes.io/name: traefik
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: 8000
    - name: traefik
      port: 8080
      protocol: TCP
      targetPort: 8080
    - name: https
      port: 443
      protocol: TCP
      targetPort: 4443
  type: LoadBalancer
  externalTrafficPolicy: "Local"
```

### Additional contract requirements

- When a load-balancer service has no explicitly configured health check, the options used to add or update the service must include a health check through the `HealthCheck` member.
