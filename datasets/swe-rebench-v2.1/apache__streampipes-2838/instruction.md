Cannot deploy a pipeline with Trend data processor
### Apache StreamPipes version

dev (current development state)

### Affected StreamPipes components

Backend

### What happened?

Error while trying to deploy a Trend Data Processor:
Error between @ Line: 1. Position: 0 and @ Line: 1. Position: 80. Syntax error in SiddhiQL, extraneous input 'Quality' expecting {STRING, INT, LONG, FLOAT, DOUBLE, BOOL, OBJECT}.

### How to reproduce?

_No response_

### Expected behavior

_No response_

### Additional technical information

_No response_

### Are you willing to submit a PR?

Yes, I am willing to submit a PR!

### Additional contract requirements

- A Trend data processor pipeline must deploy without a SiddhiQL syntax error when an input stream field name contains a space.
