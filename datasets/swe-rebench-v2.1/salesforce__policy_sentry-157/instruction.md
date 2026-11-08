when services is specified in 2 differents "wildcard-only", the former one is erased
# Description

It seems `service-*` get overridden when multiple actions is specified

# How to reproduce
CRUD config:
```yaml
service-write:
- 'eks'
service-list:
- 'eks'
```
# Expected result
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "MultMultNone",
            "Effect": "Allow",
            "Action": [
                "eks:CreateClusters",
                "eks:ListClusters"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
# Actual result

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "MultMultNone",
            "Effect": "Allow",
            "Action": [
                "eks:ListClusters"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}

```
