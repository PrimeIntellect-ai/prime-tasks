Only documents one endpoint for each path
`main.rs`
```rust
use actix_web::middleware::Logger;
use actix_web::web::Json;
use actix_web::Error as ActixError;
use actix_web::{App, HttpServer};
use apistos::app::OpenApiWrapper;
use apistos::info::Info;
use apistos::server::Server;
use apistos::spec::Spec;
use apistos::web;
use apistos::{api_operation, ApiComponent};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::net::Ipv4Addr;

#[derive(Serialize, Deserialize, Debug, Clone, ApiComponent, JsonSchema)]
pub struct Experiment {}

#[api_operation(summary = "Get")]
pub async fn get() -> Result<Json<Experiment>, ActixError> {
    unimplemented!()
}
#[api_operation(summary = "Post")]
pub async fn post(_data: Json<Experiment>) -> Result<Json<i64>, ActixError> {
    unimplemented!()
}

#[actix_web::main]
async fn main() -> Result<(), impl Error> {
    HttpServer::new(move || {
    let spec = Spec {
      info: Info {
        title: "A well documented API".to_string(),
        description: Some(
          "This is an API documented using Apistos,\na wonderful new tool to document your actix API !".to_string(),
        ),
        ..Default::default()
      },
      servers: vec![Server {
        url: "/api/v3".to_string(),
        ..Default::default()
      }],
      ..Default::default()
    };

    App::new()
        .document(spec)
        .wrap(Logger::default())
        .service(
            web::scope("/api/v1")
                .service(
                    web::scope("/experiments")
                        .route("", web::post().to(post))
                        .route("", web::get().to(get))
                    )
      )
      .build("/openapi.json")
  })
  .bind((Ipv4Addr::UNSPECIFIED, 8080))?
  .run()
  .await
}
```

`Cargo.toml`
```toml
[package]
name = "t"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.8.0"
apistos = "0.3.5"
schemars = { package = "apistos-schemars", version = "0.8" }
serde = "1.0.204"
uuid = "1.10.0"
```

Generated schema, converted to YAML for readability
```yaml
openapi: 3.0.3
info:
  title: A well documented API
  description: |-
    This is an API documented using Apistos,
    a wonderful new tool to document your actix API !
  version: ''
servers:
  - url: /api/v3
paths:
  /api/v1/experiments:
    get:
      summary: Get
      operationId: get_api-v1-experiments-703fc88c4982422c0d38cfc3589f324c
      responses:
        '200':
          description: ''
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Experiment'
      deprecated: false
components:
  schemas:
    Experiment:
      title: Experiment
      type: object

```

As you may see it does not document the `POST` endpoint. If I change the order, it only documents the `POST` endpoint and not the `GET` endpoint.

### Additional contract requirements

- The generated OpenAPI document must contain every operation that is registered. When several operations are registered for the same path, all of them must be documented under that path instead of only one.
- This applies both to operations added through repeated `route` calls on a scope that use the same sub-path (including the empty sub-path `""`) and to operations added through separate resources that share the same path.
