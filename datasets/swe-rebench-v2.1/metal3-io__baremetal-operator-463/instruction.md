Empty namespace in UserData or NetworkData part of the BMH spec defaults to default namespace
If the UserData or NetworkData object references does not have a namespace specified, the Get operation is performed on the default namespace. Should it rather default to the namespace of the BMH ?

### Additional contract requirements

- When the UserData reference has no namespace specified, retrieve its Secret from the BareMetalHost’s namespace.
- When the NetworkData reference has no namespace specified, retrieve its Secret from the BareMetalHost’s namespace.
