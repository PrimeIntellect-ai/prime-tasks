Negative cost in RemoveOtherThanSameLegsMaxGeneralizedCost filter
We are running into an issue with negative costs in our environment.

## Expected behavior

Dont crash.

## Observed behavior

```
java.lang.IllegalArgumentException: Negative value not expected for value: -168500
        at org.opentripplanner.utils.lang.IntUtils.requireNotNegative(IntUtils.java:123)
        at org.opentripplanner.utils.lang.IntUtils.requireNotNegative(IntUtils.java:130)
        at org.opentripplanner.framework.model.Cost.<init>(Cost.java:27)
        at org.opentripplanner.framework.model.Cost.costOfSeconds(Cost.java:35)
        at org.opentripplanner.routing.algorithm.filterchain.filters.transit.group.RemoveOtherThanSameLegsMaxGeneralizedCost.flagForRemoval(RemoveOtherThanSameLegsMaxGeneralizedCost.java:88)
        at org.opentripplanner.routing.algorithm.filterchain.framework.filter.RemoveFilter.filter(RemoveFilter.java:40)
        at org.opentripplanner.routing.algorithm.filterchain.framework.filter.GroupByFilter.filter(GroupByFilter.java:60)
        at org.opentripplanner.routing.algorithm.filterchain.ItineraryListFilterChain.filter(ItineraryListFilterChain.java:29)
        at org.opentripplanner.routing.algorithm.RoutingResult.transform(RoutingResult.java:66)
        at org.opentripplanner.routing.algorithm.RoutingWorker.route(RoutingWorker.java:142)
        at org.opentripplanner.routing.service.DefaultRoutingService.route(DefaultRoutingService.java:43)
        at org.opentripplanner.apis.transmodel.TransmodelGraphQLPlanner.plan(TransmodelGraphQLPlanner.java:32)
        at org.opentripplanner.apis.transmodel.model.plan.TripQuery.lambda$create$0(TripQuery.java:609)
        at graphql.execution.ExecutionStrategy.invokeDataFetcher(ExecutionStrategy.java:533)
        at graphql.execution.ExecutionStrategy.fetchField(ExecutionStrategy.java:497)
        at graphql.execution.ExecutionStrategy.fetchField(ExecutionStrategy.java:438)
        at graphql.execution.ExecutionStrategy.resolveFieldWithInfo(ExecutionStrategy.java:397)
        at graphql.execution.ExecutionStrategy.getAsyncFieldValueInfo(ExecutionStrategy.java:335)
        at graphql.execution.AsyncExecutionStrategy.execute(AsyncExecutionStrategy.java:57)
        at graphql.execution.Execution.executeOperation(Execution.java:181)
        at graphql.execution.Execution.execute(Execution.java:117)
```




## Version of OTP used (exact commit hash or JAR name)

## Steps to reproduce the problem

### Additional contract requirements

- When the sum of common transit-leg costs exceeds the minimum itinerary cost, the filter returns an empty removal list.
