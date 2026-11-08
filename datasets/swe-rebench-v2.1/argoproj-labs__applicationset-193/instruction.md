ApplicationSet conflicts with ArgoCD-Notification which cause notification spam
**ArgoCD-Notification** sets annotation to track already sent notifications:
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notified.notifications.argoproj.io: >-
      {"b620d4600c771a6f4cxxxxxxx:on-deployed:[0].y7b5sbwa2Q329JYHxxxxxx-fBs:slack:slack-test":1617144614}
```
**ApplicationSet** clears external annotation on sync which leads to notification spam in the loop.
Should be related: https://github.com/argoproj-labs/applicationset/issues/154
