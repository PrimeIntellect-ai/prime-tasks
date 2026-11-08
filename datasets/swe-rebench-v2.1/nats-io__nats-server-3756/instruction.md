Nats Server is ignoring Jetstreams limits in case of 0 byte files and grows uncontrolled
## Defect

We discovered that some Nats brokers are running over their Jetstream limits in our edge computing scenarios. We cannot completely avoid, that these devices are shut down properly, so sometimes there can occur 0 byte files.

Somehow the Nats broker seems not to be able to clear the directory, when there is a 0 byte file inside for the .blk files as shown in this screenshot:
![CleanShot 2022-12-21 at 13 10 23@2x](https://user-images.githubusercontent.com/12080409/208902456-6b749058-488f-46a3-9046-5842e4a070ee.png)

We have a limit of 1GB for our Jetstream and the max is 5 GB. The metrics show a steady rise of data, without data being removed from the Jetstream.
<img width="945" alt="CleanShot 2022-12-21 at 13 12 16@2x" src="https://user-images.githubusercontent.com/12080409/208902653-1beb135c-6dcc-4f00-ad5b-6781696f2bb6.png">

Nats does nothing strange until the 5GB limit is reached:
<img width="1192" alt="CleanShot 2022-12-21 at 13 16 57@2x" src="https://user-images.githubusercontent.com/12080409/208903377-2467550c-a31c-44d0-9c60-7cf54ec76389.png">


#### Versions of `nats-server` and affected client libraries used:

#### OS/Container environment:
containerd - nats server in version: 2.9.10-alpine

```
nats.conf: |-
    pid_file: "/var/run/nats/nats.pid"
    http: 8222

    jetstream {
      store_dir: "/data/jetstream/store"
      max_file_store: 5G
    }
```

Stream:

```yaml
---
apiVersion: jetstream.nats.io/v1beta2
kind: Stream
metadata:
  name: telemetry
  namespace: cecu-broker
spec:
  maxBytes: 1073741824
  name: telemetry
  storage: file
  subjects:
  - telemetry.*
  - telemetry.command.*
```
#### Steps or code to reproduce the issue:
Create a 0 byte file in the messages directory and wait until Jetstream is running over.

#### Expected result:
Jetstream keeps the 1 GB limit for the stream as configured.

#### Actual result:
File system is running full until Nats runs into max limit (in our case 5GB) and fails to transfer any data.
