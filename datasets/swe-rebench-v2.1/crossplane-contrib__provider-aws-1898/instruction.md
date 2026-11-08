SNS/Topic policy not applied by aws provider in crossplane
Given the following manifest, AWS provider in Crossplane does not apply the policy. Instead, it creates a Topic with the default policy.

```
apiVersion: sns.aws.crossplane.io/v1beta1
kind: Topic
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: '-50'
  labels:
    app.kubernetes.io/instance: demo-application-dev
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: fairmoney-base-chart
    argocd.argoproj.io/instance: demo-application-dev
    fairmoney.io/application: demo-application
    helm.sh/chart: fairmoney-base-chart-0.1.0
  name: fairmoney-dev-demo-application-uploads
spec:
  deletionPolicy: Delete
  forProvider:
    name: fairmoney-dev-demo-application-uploads
    policy: |
      {
        "Version": "2008-10-17",
        "Statement": [
          {
            "Sid": "AllowPublishFromS3",
            "Effect": "Allow",
            "Principal": {
              "Service": "s3.amazonaws.com"
            },
            "Action": "sns:Publish",
            "Resource": "arn:aws:sns:eu-west-1:027159582536:fairmoney-dev-demo-application-uploads",
            "Condition": {
              "ArnLike": {
                "aws:SourceArn": [
                    "arn:aws:s3:*:*:fairmoney-dev-demo-application"
                ]
              }
            }
          }
        ]
      }
    region: eu-west-1
```
**Workaround:** adding or modifying the displayName parameter will also apply the policy.

### Additional contract requirements

When a desired SNS Topic policy differs from the policy currently reported by AWS, reconciliation must apply the desired policy even when no other topic attributes need updating.
