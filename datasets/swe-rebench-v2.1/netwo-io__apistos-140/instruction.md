`.build()` Loading only the last component definitions
I have an axtic-web API that is supposed to handle the uploading of files. The API has the following routes:

- GET `/ping` - Check to see if the service is available and also return the version
- POST `/files/upload` - Upload a new file
- GET `/files/{id}/stream` - Download a file
- DELETE `/files/{id}` - Delete a file

The `/ping` route looks something like this

```rust
#[derive(Serialize, ApiComponent, JsonSchema)]
enum Status {
    Available,
}

#[derive(Serialize, ApiComponent, JsonSchema)]
struct PingResponse<'a> {
    status: Status,
    version: &'a str,
}

#[api_operation(
    summary = "Route for applications to call to see if this service is available",
    description = "Route for applications to call to see if this service is available",
    produces = "application/json"
)]
pub async fn ping() -> Json<PingResponse<'static>> {
    let version = match LOGGER.get() {
        None => "Unknown",
        Some(l) => match &l.config {
            None => "Unknown",
            Some(c) => &c.app_version,
        },
    };

    return Json(PingResponse {
        status: Status::Available,
        version,
    });
}
```

This is how i am building the app with apistos:

```rust
// ...
let app = app
    .document(spec)
    .service(resource("/ping").route(web::get().to(ping)))
    .service(
        scope("/files")
            .service(resource("/upload").route(web::post().to(upload::<
                FilesystemContext,
                FilesystemContext,
                ClientSession,
                Auth,
                FilesCollection,
                UsersCollection,
                Storage,
            >)))
            .service(resource("/{object_id}/stream").route(web::post().to(stream::<
                FilesystemContext,
                FilesystemContext,
                ClientSession,
                Auth,
                FilesCollection,
                Storage,
            >)))
            .service(resource("/{object_id}").route(web::delete().to(delete::<
                FilesystemContext,
                FilesystemContext,
                ClientSession,
                Auth,
                FilesCollection,
                FilesDatabase,
                Storage,
            >))),
    )
    .build("/spec");
// ...
```

When i now call the `/spec` route to get the spec i only get the following schemas with the PingResponse not being included.

![image](https://github.com/user-attachments/assets/b1f9c051-378a-44c2-834a-c7dcbe60308d)

I already tried to group the two services in a new `scope` with the path `""` which made the `/spec` route unreachable

```rust
// ...
 .service(
    scope("")
        .service(resource("/ping").route(web::get().to(ping)))
        .service(
            scope("/files")
                .service(resource("/upload").route(web::post().to(upload::<
                    FilesystemContext,
                    FilesystemContext,
                    ClientSession,
                    Auth,
                    FilesCollection,
                    UsersCollection,
                    Storage,
                >)))
                .service(resource("/{object_id}/stream").route(web::post().to(stream::<
                    FilesystemContext,
                    FilesystemContext,
                    ClientSession,
                    Auth,
                    FilesCollection,
                    Storage,
                >)))
                .service(resource("/{object_id}").route(web::delete().to(delete::<
                    FilesystemContext,
                    FilesystemContext,
                    ClientSession,
                    Auth,
                    FilesCollection,
                    FilesDatabase,
                    Storage,
                >))),
            ),
    )
   .build("/spec");
// ...
```

I also tried adding a `/` to the top level scope and removing it from the children, but that also didn't work.
How can i have these two routes add their models to the component definitions?
