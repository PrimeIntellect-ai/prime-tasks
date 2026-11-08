Metadata on topics and principals
This feature request is overlapping with #100, but expands on the subject.

**Is your feature request related to a problem? Please describe.**

When looking at what is deployed to a secure Kafka cluster there is often a need to know something more than topic names, schemas and which users (often represented by certificates) can read/write the topics. Important questions to answer can be:
- Who is the owner of this topic?
- What system is behind (the owner) of this principal? (Including consumer, producer, streams and connector principals)
- What topics exists within a given sub domain of our information model?
- Which systems are consuming data from a given topic? Which system is the producer?


**Describe the solution you'd like**

All of the questions above can be answered by adding your own metadata to the topology. By annotating topics and principals you can either find the information by looking into the topology files or maybe also by writing your own tools to parse the topology and produce documentation based on metadata.

In addition the metadata should be loaded into the Java model so that validations based on metadata values can be implemented.

@purbon: I have created a draft PR already to give you a clear idea of what we want. We really need this feature now and I'm ready to contribute! :-)

### Additional contract requirements

- Metadata declared for topics and for consumer, producer, stream, and connector principals must be loaded into the Java model and exposed as key-value maps through `Topic.getMetadata()` and `User.getMetadata()`, respectively. Both methods return `Map<String, String>`.
