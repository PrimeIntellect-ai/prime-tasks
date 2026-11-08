Calc Logs Are Not Being Inserted in Order
This makes things incredibly hard to debug...

![image](https://user-images.githubusercontent.com/84653157/155462528-18902925-65eb-4445-9f98-817c1157be39.png)

![image](https://user-images.githubusercontent.com/84653157/155462547-ba3b5c43-33c2-4fb1-b6ff-e8d3a7441c84.png)

Related to #287 ?

### Additional contract requirements

- The exported `Event` type in the `internal/eventlog` package must have an
  exported field with the exact declaration `Ordering map[string]int`.
- `Event.Write` must record the insertion order of each logged key in that
  `Ordering` map: the first key written is assigned the value `0`, the next `1`,
  and so on, continuing across successive `Write` calls on the same event.
