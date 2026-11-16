Resolver don't return an error in case of nested non-nullable object error
Here is a [link](https://github.com/chedom/graphql-go-tools/blob/temp/example-resolve-non-nullable-nested-object/examples/federation/start.sh) with prepared example (**product** server always returns an error for  resolving  **top-3** product).

query:
```
query {
  topProducts {
    reviews {
      product {
        price
      }
    }
  }
}
```

got:
```
{
  "data": {
    "topProducts": [
      {
        "reviews": [
          {
            "product": {
              "price": 11
            }
          },
          ...
        ]
      },
      {
        "reviews": null
      },
      {
        "reviews": [
          null
        ]
      }
    ]
  }
}
```

expected:
```
{
  "errors": [
    {
      "message": "some custom error",
      "path": [
        "_entities"
      ]
    }
  ],
  "data": {
    "topProducts": [
      {
        "reviews": [
          {
            "product": {
              "price": 11
            }
          },
       ...
        ]
      },
      {
        "reviews": null
      },
      {
        "reviews": [
          null
        ]
      }
    ]
  }
}
```
