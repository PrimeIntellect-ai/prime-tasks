Is there a way to migrate from 0.11.14 through 0.12.16 to 0.12.17+ without downtime? Target group creating empty at first
Hi, we have been using this ingress controller for years, and are currently on **0.11.14**. We have been testing upgrade to **0.12.16** which work flawlessly and, while the Cloudformation stack is updated for some reason, the actual resources don't change; there's no downtime.

If we try going to **0.12.17** however (not using the new experimental CNI), the controller comes up, updates our CF stacks, and ends up creating and attaching a new TG, while deleting the old one. The problem? This new TG has no instances in it for 30 seconds, at which point it does. This would incur a 30 seconds downtime across all of production if we went with this, not sure if we can get away with that.

Are there any flags or workarounds to prevent this? Any idea what 0.12.17 is doing differently that it needs to recreate the TG entirely, and empty at first no-less?

Screenshot of it happening right after the CF update:

![image](https://user-images.githubusercontent.com/69006307/168136708-edbc919e-59d8-47f8-bc47-a75131ebe564.png)

Logs of controller as it comes up on new 0.12.17 image (from 0.11.14)



```
time="2022-05-12T17:38:11Z" level=info msg="starting /kube-ingress-aws-controller v0.12.17"
--
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Kubernetes API server: "
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Cluster ID: jason-dev-9999999-us-east-2"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="VPC ID: vpc-9999999999"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Instance ID: i-05ded1d34e4817610"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Security group ID: sg-018f425e420f2db38"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Internal subnet IDs: [subnet-046134d61fe120cbc subnet-09fa2d9414fe47482 subnet-0f876b2913eb84f4b]"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Public subnet IDs: [subnet-06f1a762865b7ad3c subnet-086df96fe15ae9076 subnet-013c830b5b448157e]"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="EC2 filters: tag:kubernetes.io/cluster/jason-dev-418023852230-us-east-2=owned tag-key=k8s.io/role/node"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Certificates per ALB: 24 (SNI: true)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Blacklisted Certificate ARNs (0): "
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Ingress class filters: alb-istio"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="ALB Logging S3 Bucket: "
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="ALB Logging S3 Prefix: "
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="CloudWatch Alarm ConfigMap: "
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Default LoadBalancer type: application"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Target access mode: HostPort"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=warning msg="Disabling RouteGroup support because listing RouteGroups failed: resource not found, to get more information https://opensource.zalando.com/skipper/kubernetes/routegroups/#routegroups"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 3 owned auto scaling group(s)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 3 targeted auto scaling group(s)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 0 single instance(s)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 0 EC2 instance(s)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 16 certificate(s)"
Thu, May 12 2022 1:40:17 pm | time="2022-05-12T17:40:17Z" level=info msg="Found 0 cloudwatch alarm configuration(s)"
Thu, May 12 2022 1:40:21 pm | time="2022-05-12T17:40:21Z" level=info msg="Updating \"internet-facing\" stack for 1 certificates / 1 ingresses"
Thu, May 12 2022 1:40:21 pm | time="2022-05-12T17:40:21Z" level=info msg="Stack \"arn:aws:cloudformation:us-east-2:999999999:stack/kube-ingress-aws-controller-jason-dev-99999999-us-east-2-a173ffb1-df89-4dfc-86ef-d3e3c8495134/d0bb7440-d208-11ec-86f2-028a53c58cfe\" for certificate map[\"arn:aws:acm:us-east-2:99999999:certificate/eeb15f56-192c-41e5-be87-f1edfb9d9c57\":\"0001-01-01 00:00:00 +0000 UTC\"] updated"
Thu, May 12 2022 1:40:21 pm | time="2022-05-12T17:40:21Z" level=info msg="Updating \"internet-facing\" stack for 1 certificates / 1 ingresses"
Thu, May 12 2022 1:40:21 pm | time="2022-05-12T17:40:21Z" level=info msg="Stack \"arn:aws:cloudformation:us-east-2:999999999:stack/kube-ingress-aws-controller-jason-dev-999999999-us-east-2-c8b74d37-e541-42da-805e-026509a41812/11bd7aa0-b1da-11ec-85d9-062a1dd6a318\" for certificate map[\"arn:aws:acm:us-east-2:99999999:certificate/eeb15f56-192c-41e5-be87-f1edfb9d9c57\":\"0001-01-01 00:00:00 +0000 UTC\"] updated"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 3 owned auto scaling group(s)"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 3 targeted auto scaling group(s)"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 0 single instance(s)"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 0 EC2 instance(s)"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 16 certificate(s)"
Thu, May 12 2022 1:40:51 pm | time="2022-05-12T17:40:51Z" level=info msg="Found 0 cloudwatch alarm configuration(s)"


```

### Additional contract requirements

The controller must allow upgrading from versions before `0.12.17` without recreating
the load balancer target group (and therefore without downtime). This is controlled by
the `--target-access-mode` flag, which accepts exactly three values:

- `HostPort`: the CloudFormation target group `TargetType` is set to `instance`.
- `AWSCNI`: the CloudFormation target group `TargetType` is set to `ip`.
- `Legacy`: the CloudFormation target group `TargetType` is left unset, so that
  CloudFormation applies its default (`instance`). This keeps the target group
  unchanged when upgrading from a version that did not set `TargetType`.

The public method `Adapter.WithTargetAccessMode(mode string) *Adapter` applies the
selected mode. The target type it selects is reflected in the CloudFormation template
produced by `Adapter.CreateStack` and `Adapter.UpdateStack`: the target group resource
named `TG` has `TargetType` set to `instance` for `HostPort`, `ip` for `AWSCNI`, and
unset for `Legacy`. `WithTargetAccessMode` also enables AWS CNI mode
(`Adapter.TargetCNI.Enabled`) for `AWSCNI` and disables it for `HostPort` and `Legacy`.
