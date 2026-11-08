screenshots docs are duplicated across journeys
+ As we utilize the global cache path, on each journey end we end up writing the same docs that was already written on the previous journey resulting in N*M screenshot docs where N is the number of journeys and M is the number of steps.

### Additional contract requirements

When screenshots are enabled, the run reports a screenshot document for every step in each journey. A screenshot document from a completed journey must not be reported again for a later journey.
