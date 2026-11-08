EventBridge targets are not identified by moto when parsing cloudformation file.
Hi,
I'm using a cloudformation file to create my test setup. The scenario is simple: put an event, use a rule to move that event to SQS, and use an InputTransformer to change the event a bit.
When loading the CFT, all is good, except that the target is not identified, and therefore the event is not present in the queue.
When I add a target using boto3 code (same target from the CFT), I can see the event in the queue (although it is not transformed - not sure if I did something wrong, or if it doesn't work as well)

using python 3.12.2
moto[all]==5.0.2
boto3==1.34.55
cfn-flip==1.3.0
pytest==8.0.2
(running on windows, I suspect it shouldn't matter, but just in case)

Full details below, but the important part is this:
Before I run `events_client.put_targets`
the result of `events_client.list_targets_by_rule(EventBusName=event_bus_name,Rule=events_client.list_rules(EventBusName=event_bus_name)['Rules'][0]['Name'])`  the target list is empty (and a message is not put in SQS).
After I run `events_client.put_targets`, using the same data parsed from the CFT (had to manually replace the ARN, as the function was not accepted by moto, which makes sense to me) - the target is present, and events are getting to SQS.




I'm using the following CFT:
```
Resources:
  MyEventBus:
    Type: AWS::Events::EventBus
    Properties:
      Name: "TestEventBusName"

  DestQueue:
    Type: AWS::SQS::Queue

  MyQueuePolicy:
    Type: AWS::SQS::QueuePolicy
    Properties:
      PolicyDocument:
      Version: 2012-10-17
      Statement:
        - Effect: Allow
          Principal:
          Service: events.amazonaws.com
          Action: sqs:SendMessage
          Resource: !GetAtt DestQueue.Arn
          Condition:
            ArnEquals:
              aws:SourceArn: !GetAtt MyRule.Arn
        - Effect: Allow
          Principal:
            Service: events.amazonaws.com
          Action: sqs:SendMessage
          Resource: !GetAtt DestQueue.Arn
          Queues:
            - !Ref DestQueue

  MyRule:
    Type: AWS::Events::Rule
    Properties:
      EventBusName: !GetAtt MyEventBus.Name
      EventPattern:
        source:
          - my.source
        detail-type:
          - Malicious
      State: ENABLED
      Targets:
        - Id: meh
          Arn: !GetAtt DestQueue.Arn
          InputTransformer:
            InputPathsMap:
              account: $.account
              detail: $.detail
              detail-type: $.detail-type
              id: $.id
              region: $.region
              resources: $.resources
              time: $.time
            InputTemplate: "{\"id\": \"<id>\",\"detail-type\": \"<detail-type>\",\"time\":\"<time>\",\"region\": \"<region>\",\"account\": \"<account>\",\"resources\":<resources>,\"http_method\": \"POST\",\"http_endpoint\":\"/test/endpoint\",\"detail\":<detail>}"
```

my test:

```
from cfn_tools import load_yaml
import boto3
from moto import mock_aws
from assertpy import assert_that


def format_message(Detail, DetailType, EventBusName, Resources: list[str], Source):
    entry = {
PutEvents call is used.
        'Source': Source,
        'Detail': json.dumps(Detail),
        'DetailType': 'Malicious',
        'Resources': Resources,
        'EventBusName': EventBusName
    }
    return entry

#This is the important stuff - I expected to not need this
def workaround_missing_target(events_client, q_url, sqs_client, template):
    q_arn = sqs_client.get_queue_attributes(QueueUrl=q_url, AttributeNames=['All'])['Attributes']['QueueArn']
    event_bus_name = next(filter(lambda x: x['Name'] != 'default', events_client.list_event_buses()['EventBuses']))[
        'Name']
    targets = template['Resources']['MyRule']['Properties']['Targets']
    targets[0]['Arn'] = q_arn
    events_client.put_targets(
        Rule=events_client.list_rules(EventBusName=event_bus_name)['Rules'][0]['Name'],
        EventBusName=event_bus_name,
        Targets=targets,
    )


@mock_aws
def test_moto():
    path = os.path.join(os.path.dirname(__file__), 'my_template.yml')
    with open(path) as f:
        template_str = f.read()
    template = load_yaml(template_str)
    cf_client = boto3.client('cloudformation', region_name='eu-west-1')
    sqs_client = boto3.client('sqs', region_name='eu-west-1')
    events_client = boto3.client('events', region_name='eu-west-1')
    cf_client.create_stack(StackName='my-stack', TemplateBody=template_str)
    q_url = sqs_client.list_queues()['QueueUrls'][0]

    workaround_missing_target(events_client, q_url, sqs_client, template)

    entry = format_message(Detail={'a': 'b'}, DetailType=None, EventBusName='TestEventBusName',
                           Resources=["path/to/file"], Source="my.source")
    events_client.put_events(Entries=[entry])

    m = sqs_client.receive_message(QueueUrl=q_url)
    assert_that(m['Messages'][0]['Body']).contains('http_method') # assertion fails, not sure if I did something wrong, or if this is another bug
```
