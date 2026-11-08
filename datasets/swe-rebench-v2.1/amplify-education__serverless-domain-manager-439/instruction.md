Create R53 Endpoints with Latency or Weighted Base routing
The plugin currently allows only Simple routing. In cases where we want deploy API services to multiple region for DR purposes, the second custom domain has to be manually created as it overwrites the previous one. Also, how do we provide options for Routing(that than simple)

### Additional contract requirements

Custom-domain configuration must let a user choose Route 53 latency or weighted routing. The routing options are provided in `route53Params`: `routingPolicy` selects `latency` or `weighted`, and omitting it keeps simple routing. Latency-routed records must identify the deployment region. Weighted-routed records must use the configured `weight`; a weight supplied for latency routing does not turn the record into weighted routing. For either non-simple policy, a user may provide a unique `setIdentifier` so records for multiple regional endpoints can coexist under the same domain name; when omitted, the plugin must still provide an identifier that allows such records to coexist.
