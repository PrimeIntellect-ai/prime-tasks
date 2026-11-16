Add more parameters support to annotations in order to customize probe behavior.
#### What would you like to be added:

Add  numOfProbe and probeInterval annotation to supported annotation list in order to customize probe behavior.

#### Why is this needed:
Customer may want to customize health probe behavior rather than using default configuration when they are running mission critical workloads.

### Additional contract requirements

- The health probe interval is configured with the service annotation `service.beta.kubernetes.io/azure-load-balancer-health-probe-interval`. When the annotation is not set, the interval is 5 seconds. A configured value below 5 seconds is rejected.
- The number of health probes is configured with the service annotation `service.beta.kubernetes.io/azure-load-balancer-health-probe-num-of-probe`. When the annotation is not set, the number of probes is 2. A configured value below 2 is rejected.
- Both annotation values must be whole numbers; a value that is not a whole number is rejected.
- The product of the probe interval and the number of probes must be less than 120 seconds; a combination whose product is 120 seconds or more is rejected.
