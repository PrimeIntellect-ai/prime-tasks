Add endpoint to get selective_data for a content migration
**What resource needs additional coverage?**
ContentMigration

**What endpoints need to be covered?**
Endpoint name: "List items for selective import"
URLS:
* GET /api/v1/accounts/:account_id/content_migrations/:id/selective_data
* GET /api/v1/courses/:course_id/content_migrations/:id/selective_data
* GET /api/v1/groups/:group_id/content_migrations/:id/selective_data
* GET /api/v1/users/:user_id/content_migrations/:id/selective_data

Docs: https://canvas.instructure.com/doc/api/content_migrations.html#method.content_migrations.content_list

### Additional contract requirements

A `ContentMigration` provides a client-accessible `get_selective_data()` operation that retrieves the selectable items for that migration. It supports migrations belonging to accounts, courses, groups, and users.
