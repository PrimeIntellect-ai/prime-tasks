Missing descriptions after bumping from 3.5.4 to 3.5.5
We just bumped Goa, and noticed the following change:
<img width="893" alt="CleanShot 2022-02-11 at 09 23 59@2x" src="https://user-images.githubusercontent.com/1005/153566720-c35272f6-2f84-478b-8db3-d97464389106.png">

This is from the following snippets:
```go
var UUID = Type("UUID", String, func() {
	Format(FormatUUID)
})

// ...
// Payload...
      Attribute("id", UUID, "Offer ID")
// ...
```

Looking at the changelog, I believe it's due to [this change](https://github.com/goadesign/goa/pull/2991).
