Support multi-protocol ports on containers
<!--Please make sure to read the "Reporting Issues" section of the contribution guide before submitting an issue
https://github.com/cdk8s-team/cdk8s/blob/master/CONTRIBUTING.md#reporting-issues
-->

### Description of the bug:
There are some situations where the same port on a container can serve multiple protocols. One example being DNS servers typically serving both TCP and UDP traffic from port 53. The `Container` construct, however, fails when a port number repeats, even if the specified protocol is different.

There are examples of specifying the same port multiple times with different protocols. One below is an example of a `docker-compose.yml` file where this happens:
```
version: "2.1"
services:
  blocky:
    image: spx01/blocky
    container_name: blocky
    restart: unless-stopped
    # Optional the instance hostname for logging purpose
    hostname: blocky-hostname
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "4000:4000/tcp"
    environment:
      - TZ=Europe/Berlin # Optional to synchronize the log timestamp with host
    volumes:
      # Optional to synchronize the log timestamp with host
      - /etc/localtime:/etc/localtime:ro
      # config file
      - ./config.yml:/app/config.yml
```

### Reproduction Steps:
Synth the following `Deployment` in any context
```
new Deployment(app, 'test-depl', {
    containers: [{
        name: 'blocky',
        ports: [{
                name: 'dns-tcp',
                number: 53,
                protocol: Protocol.TCP,
            }, {
                name: 'dns-udp',
                number: 53,
                protocol: Protocol.UDP,
            }, {
                name: "http",
                number: 4000,
                protocol: Protocol.TCP,
            }],
    }],
});
```


### Error Log:
As of `cdk8s-plus-27@2.7.70` trying to specify the same port number twice results in the following error:
```
Error: Port with number 53 already exists
    at Container.addPort (/Users/wyvernzora/Code/k2/gitops/infra/dns/node_modules/cdk8s-plus-27/src/container.ts:830:13)
    at new Container (/Users/wyvernzora/Code/k2/gitops/infra/dns/node_modules/cdk8s-plus-27/src/container.ts:770:12)
   ...
```

### Environment:


  - **Framework Version**:
      - `cdk8s-cli@2.198.21`
      - `cdk8s@2.68.22`
      - `cdk8s-plus-27@2.7.70`
  - **OS**: MacOS Sonoma 14.2


### Other:
[HIDDEN] Or, alternatively, allow specifying multiple protocols per ContainerPort.

---

This is :bug: Bug Report

### Additional contract requirements

A container may have multiple port definitions with the same number when their protocols differ. This applies both to ports supplied when creating a container and to ports added afterwards. When a Deployment is synthesized, its container specification must include each configured same-number port with its corresponding protocol. A second definition with the same number and protocol as an existing port must be rejected.
