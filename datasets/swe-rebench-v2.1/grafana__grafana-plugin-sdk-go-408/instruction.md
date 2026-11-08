Improve the meta test comparision for golden files
When trying to test with a custom meta object the test fails because the object is not compared to the same type it can load from JSON:

```
               Meta: &data.FrameMeta{
        - 		Custom: map[string]interface{}{
        - 			"finishTime": float64(2222),
        - 			"queryId":    string("$queryId$"),
        - 			"startTime":  float64(1111),
        - 		},
        + 		Custom:  &models.TimestreamCustomMeta{StartTime: 1111, FinishTime: 2222, QueryID: "$queryId$"},
          		Stats:   nil,
```
