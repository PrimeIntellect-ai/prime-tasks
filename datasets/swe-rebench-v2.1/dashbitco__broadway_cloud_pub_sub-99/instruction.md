Issue with v.0.9.0: no function clause matching in BroadwayCloudPubSub.PullClient.decode_message/1
Hello everyone,

We've encountered an issue after upgrading to version v0.9.0:
```
** (FunctionClauseError) no function clause matching in BroadwayCloudPubSub.PullClient.decode_message/1
     (broadway_cloud_pub_sub 0.9.0) lib/broadway_cloud_pub_sub/pull_client.ex:172:
BroadwayCloudPubSub.PullClient.decode_message(%{"attributes" => %{"bucketId" => "local-warehouse-bucket",
"eventTime" => "2024-04-30 14:11:38.234127", "eventType" => "OBJECT_FINALIZE",
"notificationConfig" => "projects/local-warehouse/buckets/local-warehouse-bucket/notificationConfigs/1",
"objectGeneration" => "1", "objectId" => "ba2b0c6d-b5ce-4993-90f3-3271c04f137b/29-04-2024.png",
"payloadFormat" => "NONE"}, "messageId" => "1", "publishTime" => "2024-04-30T14:11:38.309Z"})
```

We use broadway_cloud_pub_sub to handle Pub/Sub notifications for Cloud Storage. However, in our notification configuration, we specify the payloadFormat as 'NONE', indicating no payload.

Here's an example of the message structure passing into decode_message:
```
%{
    "attributes" => %{
      "bucketId" => "local-warehouse-bucket",
      "eventTime" => "2024-05-01 13:07:41.635336",
      "eventType" => "OBJECT_FINALIZE",
      "notificationConfig" => "projects/local-warehouse/buckets/local-warehouse-bucket/notificationConfigs/1",
      "objectGeneration" => "1",
      "objectId" => "ba2b0c6d-b5ce-4993-90f3-3271c04f137b/30-04-2024.png",
      "payloadFormat" => "NONE"
    },
    "messageId" => "1",
    "publishTime" => "2024-05-01T13:07:41.716Z"
  }
```
As you can see, there is no data key in this message.

In version v0.7.0, even with payloadFormat set to NONE, a data key was added to the message. Here's an example of the message passing through decode_message:
```
% GoogleApi.PubSub.V1.Model.PubsubMessage{
  attributes: % {
    "bucketId" => "local-warehouse-bucket",
    "eventTime" => "2024-05-01 18:31:24.996117",
    "eventType" => "OBJECT_FINALIZE",
    "notificationConfig" => "projects/local-warehouse/buckets/local-warehouse-bucket/notificationConfigs/1",
    "objectGeneration" => "1",
    "objectId" => "ba2b0c6d-b5ce-4993-90f3-3271c04f137b/justine-18-03-2024.png",
    "payloadFormat" => "NONE"
  },
    data: nil,
      messageId: "1",
        orderingKey: nil,
          publishTime: ~U[2024-05-01 18: 31: 25.191Z]
}
```

Elixir: 1.12.3
Erlang: 24.1

Any suggestions or assistance would be greatly appreciated! 🙂
