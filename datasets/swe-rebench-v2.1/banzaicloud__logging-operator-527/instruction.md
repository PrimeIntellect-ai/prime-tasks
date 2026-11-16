fields column in Splunk Hec output plugin is not working .
**Describe the bug**:
fields column in Splunk Hec output plugin is not converting as per fluentd spec in fluentd.conf in secret file

**Expected behaviour**:
```
kind: ClusterOutput
metadata:
 name: splunk-output
spec:
 splunkHec:
    hec_host: http-inputs-
    hec_port: 443
    hec_token:
        valueFrom:
           secretKeyRef:
              name:  splunk-token
              key: SplunkHecToken
    index: qa_main
    fields:
      dummy: " "
    format:
      type: single_value
      message_key: MESSAGE
```
expected config in fluentd.conf ( in secrets)
```
 <fields>
     dummy
 </fileds>
```
what i get is
 fields {"dummy":" "}

so logging operator cannot separate dummy from original message to an indexed field.

**Steps to reproduce the bug**:
```
kind: ClusterOutput
metadata:
 name: splunk-output
spec:
 splunkHec:
    hec_host: http-inputs-
    hec_port: 443
    hec_token:
        valueFrom:
           secretKeyRef:
              name:  splunk-token
              key: SplunkHecToken
    index: qa_main
    fields:
      dummy: " "
    format:
      type: single_value
      message_key: MESSAGE
 ```

**Additional context**:
the main idea is to separate dummy from the original message to an indexed field in Splunk. But when using above config there is no change in the original message. but when I edited secrets to change fluentd.conf  to
```
 <fields>
     dummy
 </fileds>
```
 instead of  fields {"dummy":" "}  then I could see the change in my Splunk output . So I doubt that Splunk output plugin in logging operator is not writing the correct format to underlying fluentd.conf
**Environment details**:
- Kubernetes version (v1.15.11):
- Cloud-provider/provisioner ( EKS):
- logging operator version : 3.2.0-rc1
- Install method (static manifests):
- Resource definition (possibly in YAML format) that caused the issue, without sensitive data:
```
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterOutput
metadata:
 name: splunk-output
spec:
 splunkHec:
    hec_host: http-splunkcloud.com
    hec_port: 443
    hec_token:
        valueFrom:
           secretKeyRef:
              name:  splunk-token
              key: SplunkHecToken
    index: qa_main
    fields:
       dummy: " "
    format:
      type: single_value
      message_key: MESSAGE
      add_newline: true
```
/kind bug
