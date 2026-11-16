Nested join - object returned with all fields set to None
First mentioned in #101 by @Justinianus2001:

"
I aim to retrieve a project and its nested objects based on client_id, department_id, and assignee_id as follows:

```python
db_project = await crud_projects.get_joined(
    db=db, id=id, is_deleted=False, nest_joins=True, schema_to_select=ProjectRead,
    joins_config=[
        JoinConfig(
            model=Client,
            join_on=Project.client_id == Client.id,
            join_prefix="client",
            schema_to_select=ClientRead,
            join_type="left",
        ),
        JoinConfig(
            model=Department,
            join_on=Project.department_id == Department.id,
            join_prefix="department",
            schema_to_select=DepartmentRead,
            join_type="left",
        ),
        JoinConfig(
            model=User,
            join_on=Project.assignee_id == User.id,
            join_prefix="assignee",
            schema_to_select=UserReadSub,
            join_type="left",
        ),
    ],
)
```

However, I encounter an issue: when a foreign key is null, the object is still returned but with all fields set to None.

```python
{
    'id': 1,
    'project_code': 'ABC1',
    'status': 'Approved',
    'name': 'Project Example',
    'start_date': datetime.datetime(2024, 6, 5, 9, 26, 48, 914000, tzinfo=datetime.timezone.utc),
    'end_date': datetime.datetime(2024, 6, 5, 9, 26, 48, 914000, tzinfo=datetime.timezone.utc),
    'client': {
        'name': None,
        'contact': None,
        'phone': None,
        'email': None,
        'id': None
    },
    'department': {
        'id': 1,
        'name': 'Department Name'
    },
    'assignee': {
        'id': None,
        'name': None,
        'username': None,
        'email': None,
        'phone': None,
        'profile_image_url': None,
        'department_id': None,
        'company_id': None
    }
}
```

How can I modify the query so that if a nested object's foreign key is null, the entire nested object is returned as None (e.g., 'client': None)?
"

### Additional contract requirements

- `FastCRUD.get_multi_joined` returns its rows under the `"data"` key. When
  `return_as_model` is `False` (the default), each row in `"data"` is a
  dictionary; when `return_as_model` is `True`, each row is an instance of
  `schema_to_select`.
