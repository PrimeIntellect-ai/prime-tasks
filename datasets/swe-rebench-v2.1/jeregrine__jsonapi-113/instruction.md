Empty has-many relationship does not appear in relationships
According to [the spec](http://jsonapi.org/format/#document-resource-object-linkage), an empty to-many relationship should be represented as an empty array in `relationships`. So something like this:

```
%{
  id: 1,
  text: "Hello",
  body: "Hello world",
  author: %{id: 2, username: "jason"},
  best_comments: []
}
```

would have a `relationships` field something like this:

```
{
  relationships: %{
    author: %{
      data: %{id: "2", type: "user"},
      links: %{related: "/user/2", self: "/mytype/1/relationships/author"}
    },
    best_comments: %{
      data: [],
      links: %{
        self: "/mytype/1/relationships/best_comments"
      }
    }
  }
}
```

Currently, the serializer omits an empty to-many relationship, so it looks like this:


```
{
  relationships: %{
    author: %{
      data: %{id: "2", type: "user"},
      links: %{related: "/user/2", self: "/mytype/1/relationships/author"
    }
  }
}
```

The [test for handling an empty relationship](https://github.com/jeregrine/jsonapi/blob/master/test/serializer_test.exs#L184), specifies this behavior, but it seems to be at odds with the spec.

Would you accept a PR to serialize empty to-many relationships as empty lists? The change would definitely change responses for users of the library, but in a good way I think, bringing responses more in line with the spec.
