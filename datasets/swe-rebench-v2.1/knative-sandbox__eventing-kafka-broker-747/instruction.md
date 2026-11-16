Trigger related to KafkaBroker creation failed
**Describe the bug**
When I'm trying to create a trigger related to KafkaBroker I receive a following error:
"broker not found in data plane config map knative-eventing/kafka-broker-brokers-triggers"

It creates a new ConfigMap knative-eventing/kafka-broker-brokers-triggers, but it is empty and I can't find any reference what I should to put there.

 **Expected behavior**
Trigger is created without any errors

 **To Reproduce**
Create a trigger related to Kafka broker

 **Knative release version**
0.21

### Additional contract requirements

- When a related Broker is not ready and has the failure reason `wrong`, reconciliation must update the Trigger status with a failure condition whose reason is `wrong` and whose message is empty.
