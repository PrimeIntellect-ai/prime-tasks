Unassigne user from issue
Hi,

I would like to unassigne a user from an issue but without assigning the issue to an another user.

It is possible to do it with a PUT request to `issues/_issue_id_.json` endpint with the following body:
```
{
    "issue": {
        "assigned_to_id": ""
    }
}
```
I tried the same with this client using the following code snippet:
```
$redmineClient->issue->update($issueId, [
    'assigned_to_id' => ''
]);
```
But the `sanitizeParams()` method eliminates the empty `assigned_to_id` field.

So, my question is: how can I unassigne a user from an issue and leave the issue unassigned?

### Additional contract requirements

- When calling `update(5, ['assigned_to_id' => ''])`, the client must send a PUT request to `/issues/5.xml` with an XML body that starts with `<?xml version="1.0"?>` followed by a newline and `<issue>`, contains `<assigned_to_id></assigned_to_id>`, and ends with `</issue>` followed by a newline.
- - When calling `update(5, ['assigned_to_id' => 5])`, the client must send a PUT request to `/issues/5.xml` with an XML body that starts with `<?xml version="1.0"?>` followed by a newline and `<issue>`, contains `<assigned_to_id>5</assigned_to_id>`, and ends with `</issue>` followed by a newline.
