When the server returns an error with an empty string message, `GraphQLError.message` becomes an object instead of a string
### Describe the bug

<img width="469" alt="react code" src="https://github.com/user-attachments/assets/ec5ae634-f06a-46e6-80f8-cb4d74c67740">

### If the server returns an non-empty string as `message`
<img width="242" alt="スクリーンショット 2024-08-05 14 47 03" src="https://github.com/user-attachments/assets/2a2870d1-208a-45a6-9664-a71db079b711">

Response
![スクリーンショット 2024-08-05 14 47 29](https://github.com/user-attachments/assets/c2c72a52-ea82-4c23-9114-8465089bad8e)

CombinedError
![スクリーンショット 2024-08-05 14 46 49](https://github.com/user-attachments/assets/68454c80-3da3-4a60-9e52-a884e0d52295)

### If the server returns an empty string as `message`
<img width="228" alt="server throws error" src="https://github.com/user-attachments/assets/745a88ed-d7c0-4bd1-9de8-a1acd4b7bc72">

Response
![スクリーンショット 2024-08-05 14 45 29](https://github.com/user-attachments/assets/814d17dd-8294-4e51-a1d1-b4e870822ea2)

CombinedError
![スクリーンショット 2024-08-05 14 45 05](https://github.com/user-attachments/assets/e6108158-83f6-49dc-9e93-a45733c901c2)

[HIDDEN]



### Reproduction

https://github.com/koutaro-masaki/urql-issue-reproduction

### Urql version

urql v4.1.0

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)

### Additional contract requirements

- An empty string is a valid GraphQL error message. When a GraphQL error with `message: ""` is normalized, its `GraphQLError.message` must remain `""`, not become an object.
- When such an error is included in a `CombinedError`, the combined `message` must remain a string; with only that GraphQL error, it is `[GraphQL] `.
