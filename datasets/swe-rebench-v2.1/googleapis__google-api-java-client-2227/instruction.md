AbstractGoogleClientRequest.initializeMediaUpload is not using applicationName to User-Agent HTTP header
Internal bug b/252963877. mediaHttpUploader is not adding a proper User-Agent HTTP header.

```
        String userAgent = "Foo/1.0";
        Storage storage = new Storage.Builder(rf.getTransport(), jsonFactory, rf.getInitializer())
            .setApplicationName(userAgent)
            .build();
...
        Insert insert = storage.objects().insert(bucket, storageObject, content);
        GenericUrl url = insert.buildHttpRequestUrl();
        MediaHttpUploader mediaHttpUploader = insert.getMediaHttpUploader();

        // This does not add the expected user-agent header to the request.
        HttpResponse upload = mediaHttpUploader.upload(url);
```

#### Environment details

1. Specify the API at the beginning of the title. For example, "BigQuery: ...").
   General, Core, and Other are also allowed as types
2. OS type and version:
3. Java version:
4.  version(s):

The `com.google.apis:google-api-services-storage:v1-rev20220705-2.0.0` and `google-api-client:2.0.0`.


#### Steps to reproduce

Declare dependencies:

```
    <dependency>
      <groupId>com.google.apis</groupId>
      <artifactId>google-api-services-storage</artifactId>
      <version>v1-rev20220705-2.0.0</version>
    </dependency>
```



#### Code example

```java
    // Run with VM option to have -Djava.util.logging.config.file=src/main/resources/logging.properties
    public static void main( String[] args ) throws Exception {
        NetHttpTransport transport = new NetHttpTransport.Builder()
            .trustCertificates(GoogleUtils.getCertificateTrustStore())
            .build();
        HttpRequestFactory rf = transport.createRequestFactory();
        JsonFactory jsonFactory = new GsonFactory();

        String userAgent = "Foo/1.0";
        Storage storage = new Storage.Builder(rf.getTransport(), jsonFactory, rf.getInitializer())
            .setApplicationName(userAgent)
            .build();


        // Project suztomo-terraform-4f9e48 has this bucket.
        String bucket = "suztomo_test_b252963877"; // TODO: replace with your bucket

        StorageObject storageObject = new StorageObject().setName("temp.txt").setBucket(bucket);
        byte[] bytes = "hi".getBytes(StandardCharsets.UTF_8);
        ByteArrayInputStream bais = new ByteArrayInputStream(bytes);
        InputStreamContent content = new InputStreamContent("text/plain", bais);

        Insert insert = storage.objects().insert(bucket, storageObject, content);
        GenericUrl url = insert.buildHttpRequestUrl();
        MediaHttpUploader mediaHttpUploader = insert.getMediaHttpUploader();

        // This does not add the expected user-agent header to the request.
        HttpResponse upload = mediaHttpUploader.upload(url);
        System.out.println("Upload response code: " + upload.getStatusCode() + " " + upload.getStatusMessage());
    }
```

This does not send the user agent to the server.


#### External references such as API reference guides

- ?

#### Any additional information below

Internal bug b/252963877.

Setting request initializer as the 3rd argument to `Storage.Builder` is the workaround:

```
        HttpCredentialsAdapter credentialsInitializer = new HttpCredentialsAdapter(credentials);
        HttpRequestInitializer requestInitializer = new HttpRequestInitializer() {
            @Override
            public void initialize(HttpRequest request) throws IOException {
                credentialsInitializer.initialize(request);
                HttpHeaders headers = request.getHeaders();
                headers.setUserAgent(userAgent);
            }
        };

...(omit)...

        Storage storage = new Storage.Builder(rf.getTransport(), jsonFactory, requestInitializer)
            .setApplicationName(userAgent)
            .build();
```

But the library users shouldn't need to do that.

### Additional contract requirements

When a client has an application name, HTTP requests used for media uploads must include that name in the `User-Agent` header. A request initializer supplied by the caller must still be applied to media-upload requests, so caller setup such as credential initialization remains effective.
