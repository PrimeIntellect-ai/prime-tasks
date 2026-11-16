Actix: type alias makes Option<T> required
Having a schema like this:
```rust
type Email = Option<String>;

#[derive(Apiv2Schema, Serialize)]
struct User {
    id: i32,
    username: String,
    email: Email,
}
```

The `email` field is optional, but in the generated spec it is shown as required (`"required":["email","id","username"]`)

Full code:
```rust
use actix_web::{App, HttpServer};
use paperclip::actix::web::{self, Json};
use paperclip::actix::{api_v2_operation, Apiv2Schema, OpenApiExt};
use serde::Serialize;

type Email = Option<String>;

#[derive(Apiv2Schema, Serialize)]
struct User {
    id: i32,
    username: String,
    email: Email,
}

#[api_v2_operation]
async fn example() -> Json<User> {
    Json(User {
        id: 1,
        username: "john".into(),
        email: None,
    })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .wrap_api()
            .route("/", web::get().to(example))
            .with_json_spec_at("/api/spec")
            .build()
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
```

Cargo.toml:
```toml
[dependencies]
actix-web = "3"
paperclip = { git = "https://github.com/wafflespeanut/paperclip", features = ["actix"] }
serde = { version = "1.0", features=["derive"] }
```
