Implement updating an image
https://docs.hetzner.cloud/#resources-images-put

### Additional contract requirements

- Add a public type `ImageUpdateOpts` in package `hcloud` with fields `Description *string` and `Type ImageType`.
- Add a public method `Update(ctx context.Context, image *Image, opts ImageUpdateOpts) (*Image, *Response, error)` on `ImageClient` in package `hcloud`.
- `Update` sends a `PUT` request to `/images/{id}`, where `{id}` is the image's ID, with a JSON body that carries the `description` and/or `type` fields when they are set. When `Type` is empty it is omitted from the request body.
- `Update` parses a response body of the form `{"image": {...}}` and returns the refreshed `Image`.
- `Update` returns a non-nil error when the request fails or the API responds with an error status.
