Messages cannot be stored on stream after upgrade to 2.9.7
## Defect

Nats could not store messages on the stream after upgrading the nats cluster to 2.9.7
```[ERR] JetStream failed to store a msg on stream '$G > sap': error opening msg block file [""]: open : no such file or directory```

Before the upgrade the 3 different cluster nodes reported different stream states for messages on stream.

After the upgrade the stream info looks like this:

```
Information for Stream sap created 2022-11-07 13:33:01

             Subjects: kyma.>
             Replicas: 3
              Storage: File

Options:

            Retention: Interest
     Acknowledgements: true
       Discard Policy: New
     Duplicate Window: 2m0s
    Allows Msg Delete: true
         Allows Purge: true
       Allows Rollups: false

Limits:

     Maximum Messages: unlimited
  Maximum Per Subject: unlimited
        Maximum Bytes: 900 MiB
          Maximum Age: unlimited
 Maximum Message Size: unlimited
    Maximum Consumers: unlimited


Cluster Information:

                 Name: eventing-nats
               Leader: eventing-nats-2
              Replica: eventing-nats-0, current, seen 0.00s ago
              Replica: eventing-nats-1, current, seen 0.01s ago

State:

             Messages: 0
                Bytes: 0 B
             FirstSeq: 1,303,628,312 @ 0001-01-01T00:00:00 UTC
              LastSeq: 1,303,628,311 @ 2022-11-16T11:03:13 UTC
     Active Consumers: 2
   Number of Subjects: 2
```

Make sure that these boxes are checked before submitting your issue -- thank you!

 - [ ] Included nats.go version
 - [ ] Included a [Minimal, Complete, and Verifiable example] (https://stackoverflow.com/help/mcve)

#### Versions of `nats.go` and the `nats-server` if one was involved:
previous version of nats cluster was: 2.9.6
3 nats nodes in a cluster
1 stream (replication factor 3)
2 consumers (replication factor 3)

#### OS/Container environment:
previous image [2.9.6-alpine3.16](https://hub.docker.com/layers/library/nats/2.9.6-alpine3.16/images/sha256-abb4111e51c329aba5d98f59258cbcbe33991478a70ed25a4c1b5e53a05ab284?context=explore)
upgrade image [2.9.7-alpine3.16](https://hub.docker.com/layers/library/nats/2.9.7-alpine3.16/images/sha256-d4698031a0afeb1ed37b240a9632b22a2d0fcea5fd48af3c8b28e1eba3348033?context=explore)

#### Steps or code to reproduce the issue:
it happened with the upgrade.

#### Expected result:
everything works as expected

#### Actual result:
```[ERR] JetStream failed to store a msg on stream '$G > sap': error opening msg block file [""]: open : no such file or directory```
