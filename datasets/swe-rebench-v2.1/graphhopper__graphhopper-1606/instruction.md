Edge-based bidirectional algorithms do not agree with Dijkstra when there is a loop and turn restrictions.
Here is a graph involving a loop and some turn restrictions for which the edge-based bidirectional algorithms do not agree with Dijkstra / do not find the optimal path:

https://github.com/graphhopper/graphhopper/blob/fe8df1d7e56ac6052571eaf2bfc675ba1cd6415e/core/src/test/java/com/graphhopper/routing/EdgeBasedRoutingAlgorithmTest.java#L162-L185
