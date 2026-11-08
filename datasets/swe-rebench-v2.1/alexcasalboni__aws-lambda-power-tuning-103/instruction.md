Bug: log processed payload in case of execution error
Hey @alexcasalboni, thanks for the great project. I wrapped a Lambda with it today and it gave some great insight on the ideal configuration.

One small thing that stumped me for a while that I thought I'd mention is that when you make use of a pre-processor function and it goes wrong, the payload reported in the thrown error is the original payload rather than the post-processed payload that was actually sent to the target Lambda: https://github.com/alexcasalboni/aws-lambda-power-tuning/blob/master/lambda/executor.js#L84

Cheers
