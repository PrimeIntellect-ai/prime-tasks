Enable Beeline to simultaneously accept w3c and honeycomb propagation headers
<!---
Thank you for contributing an idea to this project!

Please see our [OSS process document](https://github.com/honeycombio/home/blob/main/honeycomb-oss-lifecycle-and-practices.md#) to get an idea of how we operate.
--->

**Is your feature request related to a problem? Please describe.**

Currently, it's not possible to incrementally move a microservices architecture from the honeycomb propagation headers format to the w3c propagation headers format. This makes it difficult if not impossible for beeline customers with a large enough deployment to move towards interoperating with OpenTelemetry.

**Describe the solution you'd like**

Allow the beeline to simultaneously accept both w3c and honeycomb propagation headers, whichever is found on the incoming request. The outgoing propagation header format can still be static and set by configuration.

**Describe alternatives you've considered**


**Additional context**

### Additional contract requirements

- When an incoming request carries both the Honeycomb propagation header (`X-Honeycomb-Trace`) and the W3C propagation header (`traceparent`), the Honeycomb header is used and a warning is logged.
