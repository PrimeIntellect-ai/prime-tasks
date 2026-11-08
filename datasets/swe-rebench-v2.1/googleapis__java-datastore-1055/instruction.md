AggregationQuery doesn't respect namespace from `com.google.cloud.datastore.Datastore` object
#### Given
I have `2 entities` stored for `Task` kind under the namespace `ns1` and i configure a `com.google.cloud.datastore.Datastore` service with `ns1` namespace.

#### Scenario
When I try to run **entity** query with or without namespace through the `com.google.cloud.datastore.Datastore` object configured with namespace, i get same results, whereas in case of `AggregationQuery` i don't.

#### Code example

```java
import static com.google.cloud.datastore.aggregation.Aggregation.count;
import static com.google.common.collect.Iterables.getOnlyElement;

import com.google.cloud.datastore.AggregationQuery;
import com.google.cloud.datastore.Datastore;
import com.google.cloud.datastore.DatastoreOptions;
import com.google.cloud.datastore.Entity;
import com.google.cloud.datastore.EntityQuery;
import com.google.cloud.datastore.Query;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class Playground {

  public static void main(String[] args) {
    DatastoreOptions datastoreOptions = DatastoreOptions.newBuilder()
        .setNamespace("ns1")
        .build();
    Datastore datastore = datastoreOptions.getService();

    EntityQuery entityQueryWithNamespace = Query.newEntityQueryBuilder()
        .setKind("Task")
        .setNamespace("ns1")
        .build();

    EntityQuery entityQueryWithoutNamespace = Query.newEntityQueryBuilder()
        .setKind("Task")
        .build();

    AggregationQuery aggregationQueryWithNamespace = Query.newAggregationQueryBuilder()
        .over(Query.newKeyQueryBuilder().setKind("Task").build())
        .addAggregation(count().as("my_count"))
        .setNamespace("ns1")
        .build();

    AggregationQuery aggregationQueryWithoutNamespace = Query.newAggregationQueryBuilder()
        .over(Query.newKeyQueryBuilder().setKind("Task").build())
        .addAggregation(count().as("my_count"))
        .build();

    System.out.println("Total elements from entity query with namespace " + toList(
        datastore.run(entityQueryWithNamespace)).size());  // 2
    System.out.println("Total elements from entity query without namespace " + toList(
        datastore.run(entityQueryWithoutNamespace)).size()); // 2

    System.out.println("Total elements from aggregation query with namespace " + getOnlyElement(
        datastore.runAggregation(aggregationQueryWithNamespace)).get("my_count")); // 2
    System.out.println("Total elements from aggregation query without namespace " + getOnlyElement(
        datastore.runAggregation(aggregationQueryWithoutNamespace)).get("my_count")); // 0
  }

  private static List<Entity> toList(Iterator<Entity> results) {
    ArrayList<Entity> list = new ArrayList<>();
    while (results.hasNext()) {
      list.add(results.next());
    }
    return list;
  }

}

```
#### Problem
last query execution of `aggregationQueryWithoutNamespace` returns 0 count.

#### Explanation
If a namespace is configured in `AggragationQuery` the library will use that namespace to run that query, and if it's not present, it'll completely ignore the one configured in `com.google.cloud.datastore.Datastore` service and simply run the query in default namespace and hence the diff in output.

[HIDDEN]

Thanks!

### Additional contract requirements

- When an `AggregationQuery` has an explicitly set namespace, use that namespace for the query, even if the `Datastore` service is configured with a different namespace.
- When an `AggregationQuery` has no namespace set, use the namespace configured on the `Datastore` service rather than the default namespace.
