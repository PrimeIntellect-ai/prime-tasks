Mixin Strategy Produces Invalid Queries
### Summary
The Mixins feature is a great idea for extending the functionality of generated classes, however the mixin directive is not removed from the final generated query, resulting in errors returned from remote APIs.


### Example
Let's say that we simply want to validate that a mixin has been applied by returning a message:

```python
class RepositoryMixin:
    def test_mixin(self):
        return "This is a mixin for the Repository object!"
```
We then add it to the config TOML and include it in our GraphQL query:

```toml
files_to_include = [
    "./codegen/github_enterprise/mixins/repository_mixin.py",
]
```

```gql
query get_repository($repo_owner: String!, $repo_name: String!) {
  repository(name: $repo_name, owner: $repo_owner)
    @mixin(from: ".repository_mixin", import: "RepositoryMixin") {
    nameWithOwner
    description
  }
}
```

Looking at the generated Pydantic `BaseModel` we can see that the mixin was applied successfully:

```python
class GetRepositoryRepository(BaseModel, RepositoryMixin):
    name_with_owner: str = Field(alias="nameWithOwner")
    description: Optional[str]
```

However, the final generated query in the final generated GraphQL Client still contains the mixin directive used previously to generate our Pydantic model that inherits the mixin:

<img width="801" alt="codegen-bad-generated-query" src="https://github.com/mirumee/ariadne-codegen/assets/31744764/da4ae62c-4e13-4b09-88f1-7c5b40487bce">
<br />
<br />

Executing the `GithubEnterpriseClient.get_repository` method with this query results in `GraphQLClientHttpError: HTTP status code: 500`. Removing the mixin from the generated query fixes the error and returns the requested data, which contains a Repository on which you can successfully call the `Repository.test_mixin` method and get the expected output: `This is a mixin for the Repository object.`

### Fix


- Is the `@mixin` directive intended to be used exclusively at generation-time to inject the proper class into the inheritance chain of a given Pydantic model?
  - If yes, then can this issue be fixed by simply programming the codegen business logic to remove the mixin from the final generated query in the GraphQL client?
  - If no,  what is the use-case of preserving the mixin in the final generated query and how can one use it without remote API errors?
