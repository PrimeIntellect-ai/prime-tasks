# TaskFlow API Documentation

**Version**: 2.0
**Last Updated**: March 2024

Welcome to the TaskFlow API! This document describes how to interact with our REST API for managing tasks and projects. You can use these endpoints to build integrations with TaskFlow.

## Authentication

All API calls require a valid API key. Include your key in the `Authorization` header:

```
Authorization: Bearer <your_api_key>
```

You can generate an API key from the TaskFlow dashboard under Settings > API Keys.

---

## Tasks

### GET /api/v2/tasks

Retrieves a list of tasks for the authenticated user. The user can filter results using query parameters.

**Query Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| status | string | Filter by task status. Allowed values: `open`, `in_progress`, `done`, `archived` |
| project_id | integer | Only return tasks belonging to this project |
| page | integer | Page number for pagination (default: 1) |
| per_page | integer | Number of results per page (default: 20, max: 100) |
| sort | string | Sort field. One of `created_at`, `updated_at`, `priority` |
| order | string | Sort direction: `asc` or `desc` |

**Example Request**

```bash
curl -X GET "https://api.taskflow.io/api/v2/tasks?status=open&page=1" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

**Response** (200 OK)

```json
{
  "data": [
    {
      "id": 1042,
      "title": "Fix login bug",
      "description": "Users are unable to login with SSO",
      "status": "open",
      "priority": "high",
      "assignee_id": 57,
      "project_id": 12,
      "created_at": "2024-03-01T14:22:00Z",
      "updated_at": "2024-03-01T14:22:00Z",
      "due_date": "2024-03-15T00:00:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 98
  }
}
```

---

### POST /api/v2/tasks

Creates a new task. You must provide at least a title. The task will be created under the user's default project if `project_id` is not specified.

**Request Body Arguments**

- `title` (string, **required**) - The title of the task. Max 255 characters.
- `description` (string) - A longer description. Supports Markdown formatting.
- `status` (string) - Initial status. Defaults to `open`.
- `priority` (string) - One of: `low`, `medium`, `high`, `critical`. Default is `medium`.
- `assignee_id` (integer) - User ID to assign the task to.
- `project_id` (integer) - Project to create the task in.
- `due_date` (string) - Due date in ISO 8601 format.
- `tags` (array of strings) - Tags to apply to the task.

**Example**

```python
import requests

resp = requests.post(
    "https://api.taskflow.io/api/v2/tasks",
    headers={"Authorization": "Bearer YOUR_API_KEY"},
    json={
        "title": "Design new landing page",
        "description": "Create mockups for the Q2 marketing campaign",
        "priority": "high",
        "project_id": 12,
        "due_date": "2024-04-01T00:00:00Z",
        "tags": ["design", "marketing"]
    }
)
print(resp.json())
```

Returns `201 Created` on success with the full task object in the response body.

**Errors**

| Status Code | Meaning |
|------------|---------|
| 400 | Bad request - missing required fields or invalid values |
| 401 | Authentication failed |
| 422 | Validation error (e.g. title too long) |

---

### GET /api/v2/tasks/{id}

Get a single task by its ID.

Pass the task ID as a path parameter. Returns the task object if found. Returns 404 if the task doesn't exist or you don't have access.

Response includes the full task object (same schema as list endpoint).

No additional arguments.

---

### Updating a task - PUT /api/v2/tasks/{id}

We support partial updates - you only need to send the fields you want to change. Any fields not included in the request body will remain unchanged.

Note: the `id` and `created_at` fields cannot be modified.

**Fields you can update:**

- title
- description
- status (must be a valid status string)
- priority
- assignee_id (set to `null` to unassign)
- project_id
- due_date (ISO 8601 timestamp or null to clear)
- tags

**Sample curl command:**

```bash
curl -X PUT "https://api.taskflow.io/api/v2/tasks/1042" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"status": "in_progress", "assignee_id": 57}'
```

The API returns `200 OK` and the updated task object on success.

---

### DELETE /api/v2/tasks/{id}

Permanently deletes a task. This action cannot be undone.

The user must have admin or owner permissions on the project that the task belongs to. Regular members can only delete tasks they created.

**Returns:**

`204 No Content` on success. The response body is empty.

If the task is not found a `404` error is returned. Attempting to delete a task without sufficient permissions results in `403 Forbidden`.

---

## Projects

### List projects

```
GET /api/v2/projects
```

This route returns all projects the authenticated user has access to. Projects are returned in alphabetical order by name.

**Query args:**

- `archived` (boolean) - if `true`, include archived projects. Default `false`.
- `role` (string) - filter by the user's role in the project: `owner`, `admin`, `member`

No authentication header examples are given here since it follows the same pattern described at the top of this doc.

**Sample response:**

```json
{
  "projects": [
    {
      "id": 12,
      "name": "Website Redesign",
      "description": "Q2 2024 website overhaul",
      "owner_id": 57,
      "created": 1709312400,
      "member_count": 8,
      "task_count": 45,
      "archived": false
    }
  ]
}
```

Note that the `created` field here returns a Unix timestamp. We plan to migrate this to ISO 8601 in a future release.

---

### Create Project

**Endpoint:** `POST /api/v2/projects`

To create a new project, send a POST request with the following payload:

```json
{
  "name": "My New Project",
  "description": "Optional project description"
}
```

The `name` field is required and must be unique within the user's organization. Max 100 chars.

**Response fields:**

| Field | Type | Notes |
|-------|------|-------|
| id | integer | Auto-generated project ID |
| name | string | The project name |
| description | string | May be null |
| owner_id | integer | ID of creating user |
| created | integer | Unix timestamp |
| member_count | integer | Always 1 for new projects |
| task_count | integer | Always 0 for new projects |
| archived | boolean | Always false for new projects |

Returns HTTP 201.

No error documentation is provided here but the API follows standard REST conventions for error responses.

---

## User Info

### Getting your profile

**Route**: GET /api/v2/users/me

This returns information about the currently authenticated user. Pass your API key as usual.

The response looks like:

```json
{
  "user": {
    "id": 57,
    "email": "jane@example.com",
    "name": "Jane Smith",
    "role": "admin",
    "organization_id": 5,
    "timezone": "America/New_York",
    "created_at": "2023-01-15T09:00:00Z",
    "last_login": 1709398800
  }
}
```

Note: `created_at` is ISO 8601 but `last_login` is a Unix timestamp. This inconsistency will be addressed in API v3.

---

## Rate Limiting

We enforce rate limits to ensure fair usage of the API. The current limits are:

- 100 requests per minute for free tier
- 1000 requests per minute for paid plans

When you exceed the limit, the API returns `429 Too Many Requests`. Check the `X-RateLimit-Remaining` header to see how many requests you have left.

## Pagination

List endpoints support pagination via `page` and `per_page` query parameters. The response `meta` object contains pagination info. Note that the projects endpoint does not currently support pagination - all projects are returned in a single response.

## Errors

The API uses standard HTTP status codes. Error responses include a JSON body:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Title is required",
    "details": []
  }
}
```

However, some older endpoints may return errors in a different format:

```json
{
  "error": "not_found",
  "message": "Task not found"
}
```

We are working on standardizing error responses across all routes.

---

*For questions or support, email api-support@taskflow.io*
