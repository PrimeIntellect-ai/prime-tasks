The only way to enable jetstream for an account is by setting one (or more) limit(s) of the jetstream settings for that account
### What version were you using?

Using `nats-server` `2.10.7` and version `2.8.5` of `nsc`

### What environment was the server running in?

Mac Apple M1 Pro

### Is this defect reproducible?

```
# Create operator
nsc add operator --name local
# Add account
nsc add account APP
# Describe account
nsc describe account APP
```
This shows:

> +--------------------------------------------------------------------------------------+
|                                   Account Details                                    |
+---------------------------+----------------------------------------------------------+
| Name                      | APP                                                      |
| Account ID                | AA2XZ3FGUMJ6KA7H33336PIQQKR42JCPEFWVVARFR5VFDZHMGCL5GG52 |
| Issuer ID                 | OCQZZICCSFQ7X7PJ3H3BPBOOFLHI5VBYCOUCLCIDEQZGKOOLFKRRWRUU |
| Issued                    | 2023-12-19 02:00:08 UTC                                  |
| Expires                   |                                                          |
+---------------------------+----------------------------------------------------------+
| Signing Keys              | AANHPBG53PJY6GNPMMW7TXEXMQQQYR5W5XHCDWTVW7GI4LQEPWF4J4E6 |
+---------------------------+----------------------------------------------------------+
| Max Connections           | Unlimited                                                |
| Max Leaf Node Connections | Unlimited                                                |
| Max Data                  | Unlimited                                                |
| Max Exports               | Unlimited                                                |
| Max Imports               | Unlimited                                                |
| Max Msg Payload           | Unlimited                                                |
| Max Subscriptions         | Unlimited                                                |
| Exports Allows Wildcards  | True                                                     |
| Disallow Bearer Token     | False                                                    |
| Response Permissions      | Not Set                                                  |
+---------------------------+----------------------------------------------------------+
| Jetstream                 | Disabled                                                 |
+---------------------------+----------------------------------------------------------+
| Imports                   | None                                                     |
| Exports                   | None                                                     |
+---------------------------+----------------------------------------------------------+

With the main note that `Jetstream` is `Disabled`
```
# Set an arbitrary limit for jetstream
nsc edit account APP --js-mem-storage 10g
```

We now see `Jetstream` is enabled:

> | Jetstream                 | Enabled                                                  |
| Max Disk Storage          | Disabled                                                 |
| Max Mem Storage           | 10 GB                                                    |
| Max Streams               | Unlimited                                                |
| Max Consumer              | Unlimited                                                |
| Max Ack Pending           | Consumer Setting                                         |
| Max Ack Pending           | Unlimited                                                |
| Max Bytes                 | optional (Stream setting)                                |
| Max Memory Stream         | Unlimited                                                |
| Max Disk Stream           | Unlimited                                                |

```
# Remove that limit
nsc edit account APP --js-mem-storage -1
```

And now `Jetstream` is still enabled:

> | Jetstream                 | Enabled                                                  |
| Max Disk Storage          | Disabled                                                 |
| Max Mem Storage           | Unlimited                                                |
| Max Streams               | Unlimited                                                |
| Max Consumer              | Unlimited                                                |
| Max Ack Pending           | Consumer Setting                                         |
| Max Ack Pending           | Unlimited                                                |
| Max Bytes                 | optional (Stream setting)                                |
| Max Memory Stream         | Unlimited                                                |
| Max Disk Stream           | Unlimited                                                |

### Given the capability you are leveraging, describe your expectation?

My expectations is that there is an `Enable Jetstream` option for an account that doesn't require setting a `Jetstream` limit.

There is a `--js-disable` option, would be great to have a `--js-enable` option that enables `Jetstream` for an account without requiring any limit manipulation

### Given the expectation, what is the defect you are observing?

A `--js-enable` option (or similar) appears to be missing.
The static auth option allows for a `jetstream: enabled` option for comparison

### Additional contract requirements

- The account-edit command must accept `nsc edit account ACCOUNT --js-enable 0` to enable the account's global JetStream tier. Afterward, the disk and memory storage limits must each be `-1`.
- If the global JetStream tier is already enabled, invoking `--js-enable 0` must fail with the exact error `jetstream tier global is already enabled`.
- If `--js-enable 0` and `--rm-js-tier 0` are supplied together, the command must fail with the exact error `rm-js-tier is exclusive of all other js options`.
