Add support for function without any argument for the api_operation macro
Currently if I want to use the api_operation macro the following way, there is no problem:
```rust
#[api_operation(summary = "Get an element from the todo list")]
pub(crate) async fn get_todo(todo_id: Path<Uuid>) -> Result<Json<Todo>, Error> {
    // because it is a sample app, we do not currently implement any logic to store todos
    Ok(Json(Todo {
        id: todo_id.into_inner(),
        title: "some title".to_string(),
        description: None,
    }))
}
```
But if I want to use it like that:
```rust
#[api_operation(summary = "Get an element from the todo list")]
pub(crate) async fn get_todo() -> Result<Json<Todo>, Error> {
    // because it is a sample app, we do not currently implement any logic to store todos
    Ok(Json(Todo {
        id: Uuid::new_v4(),
        title: "some title".to_string(),
        description: None,
    }))
}
```
I get a compilation error:
```
error[E0282]: type annotations needed
  --> src/api.rs:22:1
   |
22 | #[api_operation(summary = "Get an element from the todo list")]
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ cannot infer type
   |
   = note: this error originates in the macro `vec` which comes from the expansion of the attribute macro `api_operation` (in Nightly builds, run with -Z macro-backtrace for more info)
```
