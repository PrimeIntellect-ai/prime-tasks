Support empty claims values
<!--
PLEASE DO NOT USE GITHUB ISSUES TO ASK QUESTIONS!

The JJWT team uses GitHub Issues only to track actionable work that requires changes to the JJWT codebase.

If you have a usability or general question about JJWT, please instead post your question to StackOverflow using the following JJWT-specific link:

https://stackoverflow.com/questions/ask?tags=jjwt&guided=false

To help ensure you receive a timely response, please follow the StackOverflow guidelines on how to ask a good question: https://stackoverflow.com/help/how-to-ask

Ok, now that that's out of the way - if you're still sure you need to report a bug, please fill in the sections below...
-->

**Describe the bug**
In versions before 0.12.x it was possible to add empty values in the claims of the JWT (for example `.claim("test", "")` or `.claim("test", new ArrayList<>())`). In versions after `0.12.0` empty claims are not serialized (compacted) anymore which breaks my use case where the receiving end expects the JWT to have all keys (even ones with empty values) in the claim map.

**To Reproduce**
Try to create a JWT with some claims that have empty values (See above example)
My exact code: https://github.com/RaphiMC/ViaBedrock/blob/5674c4b0a04f64b5560064ba326d8ac3e6e5403a/src/main/java/net/raphimc/viabedrock/protocol/packets/LoginPackets.java#L341

**Expected behavior**
I am expecting to be able to add empty values into the claims map (See above example)
