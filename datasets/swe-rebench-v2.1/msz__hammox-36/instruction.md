Errors on Parametrized Types
From `Ecto.Changeset`, there is a `t()` defined such as:

```elixir
  @type t(data_type) :: %Changeset{valid?: boolean(),
                        ...
                        data: data_type,
                        ...
                        types: nil | %{atom => Ecto.Type.t}}
```

In our behaviour, we have something like:

```elixir
  @type user_changeset :: Ecto.Changeset.t(User.t())

  @callback password_operation(user_changeset) :: user_changeset
  @callback password_operation(user_changeset, attrs :: map) :: user_changeset
```

In our implementation:

```elixir
  @type user_changeset :: Ecto.Changeset.t(User.t())
  @impl CredentialsHelper
  @spec password_operation(user_changeset) :: user_changeset
  @spec password_operation(user_changeset, map) :: user_changeset
  def password_operation(cs, attrs \\ %{}),
    do: ...
```

When trying to `stub` or `expect`, Hammox raises:

```
     ** (FunctionClauseError) no function clause matching in Hammox.TypeEngine.match_type/2

     The following arguments were given to Hammox.TypeEngine.match_type/2:

         # 1
         nil

         # 2
         {:var, 282, :data_type}
```

Note: we tried every possible combination of typing here - directly `Ecto.Changeset.t`, `Ecto.Changeset.t(any)` etc. Only replacing the `changeset` type by `any` *on the behaviour* seems to fix the problem.
