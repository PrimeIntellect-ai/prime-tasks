(bedrock): bedrock.ChunkingStrategy.DEFAULT doesn't deploy
### Describe the bug

using version 0.1.157, deploying bedrock datasource returns error: Resource handler returned message: "Cannot invoke "software.amazon.bedrock.datasource.ChunkingConfiguration.getChunkingStrategy()" because "modelChunkingConfiguration" is null"

### Expected Behavior

deploy successful

### Current Behavior

returns error complaining no ChunkingConfiguration

### Reproduction Steps

 this.dataSource = new bedrock.S3DataSource(this, 'DataSource', {
      bucket: this.knowledgeBaseBucket,
      knowledgeBase: this.knowledgeBase,
      dataSourceName: 'mydatasource',
      chunkingStrategy: bedrock.ChunkingStrategy.DEFAULT,
      maxTokens: 1000,
      overlapPercentage: 10,
    });

### Possible Solution

_No response_

### Additional Information/Context

_No response_

### CDK CLI Version

2.139.0 (build 2699ffd)

### Framework Version

_No response_

### Node.js Version

v20.12.2

### OS

Linux

### Language

Typescript

### Language Version

_No response_

### Region experiencing the issue

us-west-2

### Code modification

no

### Other information

_No response_

### Service quota

- [X] I have reviewed the service quotas for this construct

### Additional contract requirements

When `ChunkingStrategy.DEFAULT` is selected for an S3 data source, synthesis must include a chunking configuration using the fixed-size strategy, with a maximum of 300 tokens and 20% overlap. These defaults apply regardless of the supplied maximum-token and overlap values.
