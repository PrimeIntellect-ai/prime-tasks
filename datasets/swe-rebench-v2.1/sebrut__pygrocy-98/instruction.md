implement chore details API interface
`GET /chores​/{choreId}`
returns more information for a single chore and should be implemented like the call for product details.

### Additional contract requirements

The details response for a chore must expose the chore, its last-tracked time, its estimated next execution time, and the tracking count through the `track_count` accessor. It must also expose the last-completion user, including the user's ID and display name. When the response contains a next-execution assigned user, expose that user through `next_execution_assigned_user`, including the user's ID and display name; when no such user is present, this accessor must return `None`.
