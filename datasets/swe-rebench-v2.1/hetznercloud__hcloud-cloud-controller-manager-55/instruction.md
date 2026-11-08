health-check-interval: parsing "15s": invalid syntax
The health-check-interval annotation is set as `time.Duration` but then is attempted to be parsed as `int`.

```
Event(v1.ObjectReference{Kind:"Service", Namespace:"default", Name:"echoserver", UID:"618a5944-ff89-4042-85c3-f398036c582d", APIVersion:"v1", ResourceVersion:"1538", FieldPath:""}): type: 'Warning' reason: 'UpdateLoadBalancerFailed' Error updating load balancer with new hosts map[ubuntu-2gb-hel1-3:{}]: [HIDDEN] load-balancer.hetzner.cloud/health-check-interval: strconv.Atoi: parsing "15s": invalid syntax
```

### Additional contract requirements

Health-check interval annotation values written as Go duration strings, including `15s`, must be accepted during load-balancer service reconciliation and applied as the corresponding duration.
