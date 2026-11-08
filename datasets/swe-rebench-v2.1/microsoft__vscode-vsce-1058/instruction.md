Automatically add chatParticipant tag to extensions who are contributing chatParticipants
We should add a tag `chatParticipant` for extensions that have a non-empty `chatParticipants` contribution.
```
"contributes": {
		"chatParticipants":
```


Maybe we can also use a shorter tag name like `chat`. I am open for suggestions on tag name. Though chatParticipant might be more precise.
We will later use this in the product to allow users to discover the extensions that are contributing chatParticipants.

fyi @sandy081

### Additional contract requirements

- The tag added for extensions that contribute chat participants is exactly `chat-participant`.
