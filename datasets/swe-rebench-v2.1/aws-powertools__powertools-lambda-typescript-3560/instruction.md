Feature request: Change powertools lambda context capture log key order
### Use case

We were in the process of [enabling the capturing of the lambda context](https://docs.powertools.aws.dev/lambda/typescript/latest/core/logger/#capturing-lambda-context-info) in our logger.

Although we like the additional context, we didnt enable it because the actual logged message is only visible anymore when expanding the log message which makes it almost impossible to skim through log-message and spot the one which looks interesting because they all look the same in the x-ray-tracing-view and I would be forced to scroll sideways.

See this screenshot for reference:
![image](https://github.com/user-attachments/assets/ac507ec9-2453-4dd5-bdc6-0bf94cb85148)




### Solution/User Experience

Is it possible for you to change the order of the logging keys exposed from capturing the lambda context and put it to the end by default (or after the message)?

### Alternative solutions

```Markdown
Since v2.8.0 its also possible to define log key order on their own, see here: https://docs.powertools.aws.dev/lambda/typescript/latest/core/logger/#reordering-log-keys-position
```


### Acknowledgment

- [X] This feature request meets [Powertools for AWS Lambda (TypeScript) Tenets](https://docs.powertools.aws.dev/lambda/typescript/latest/#tenets)
- [ ] Should this be considered in other Powertools for AWS Lambda languages? i.e. [Python](https://github.com/aws-powertools/powertools-lambda-python/), [Java](https://github.com/aws-powertools/powertools-lambda-java/), and [.NET](https://github.com/aws-powertools/powertools-lambda-dotnet/)

### Future readers

Please react with 👍 and your use case to help us understand customer demand.
