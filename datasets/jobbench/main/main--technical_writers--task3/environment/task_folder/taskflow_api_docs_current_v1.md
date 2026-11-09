# TaskFlow API v1

API base URL: `https://api.taskflow.io/api`

Auth: use `X-API-Key` header with your key.

---

## GET /api/tasks

Gets tasks. Returns JSON array.

Params: `status`, `project`, `limit`, `offset`

Response: array of task objects.

---

## POST /api/tasks

Create a task.

Body: JSON with `title` (required), `desc`, `status`, `priority`, `assigned_to`, `project`, `deadline`.

`deadline` should be a Unix timestamp.

Returns the created task. 200 OK.

---

## GET /api/tasks/:id

Fetch one task.

---

## PUT /api/tasks/:id

Update task fields. Send only what changed.

---

## DELETE /api/tasks/:id

Delete a task. Must be owner.

---

## GET /api/projects

List all projects.

---

## POST /api/projects

Make a new project. Body: `name` (required), `desc`.

---

## GET /api/users/current

Get current user info.

Response:

```
{
  "id": 57,
  "email": "jane@example.com",
  "name": "Jane Smith",
  "role": "admin",
  "org": 5
}
```

---

## GET /api/tasks/:id/comments

List comments on a task.

---

## POST /api/tasks/:id/comments

Add comment. Body: `text`.

---

## GET /api/search

Search across tasks and projects.

Params: `q` (search query), `type` (task or project)

---

## PUT /api/tasks/:id/assign

Assign a task to a user. Body: `user_id`.

This is a convenience endpoint. You can also update the `assigned_to` field directly via PUT /api/tasks/:id.

---

## GET /api/tasks/:id/history

Returns change history for a task. Each entry shows what field changed, old value, new value, who changed it, and when (Unix timestamp).

---

## DELETE /api/projects/:id

Delete a project. All tasks in the project will also be deleted.

---

## Errors

Errors return JSON: `{"error": "message"}`.

Common codes: 400, 401, 404, 500.

---

## Webhooks

POST /api/webhooks - register a webhook. Body: `url`, `events` (array).

GET /api/webhooks - list webhooks.

DELETE /api/webhooks/:id - remove a webhook.

Events: `task.created`, `task.updated`, `task.deleted`, `project.created`.

---

## Notes

- Rate limit: 60 req/min.
- All timestamps are Unix.
- Contact support@taskflow.io for help.
