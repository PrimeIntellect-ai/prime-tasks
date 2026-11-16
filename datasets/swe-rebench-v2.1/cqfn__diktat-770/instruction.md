Bugs during autofix of KDoc
## Describe the bug
Initial code:
```kotlin
    /**
     * Creates a docker container with [file], prepared to execute it
     *
     * @param runConfiguration a [RunConfiguration] for the supplied binary
     * @param file a file that will be included as an executable
     * @param resources additional resources
     * @throws DockerException if docker daemon has returned an error
     * @throws DockerException if docker daemon has returned an error
     * @throws RuntimeException if an exception not specific to docker has occurred
     * @return id of created container or null if it wasn't created
     */
    internal fun createWithFile(runConfiguration: RunConfiguration,
                                containerName: String,
                                file: File,
                                resources: Collection<File> = emptySet()): String {}
```
result after `diktatFix`:
```kotlin
    /**
     * Creates a docker container with [file], prepared to execute it
     *
     * @param runConfiguration a [RunConfiguration] for the supplied binary
     * @return id of created container or null if it wasn't created
     * @throws DockerException if docker daemon has returned an error
     * @throws DockerException if docker daemon has returned an error
     * @throws DockerException if docker daemon has returned an error
     * @throws RuntimeException if an exception not specific to docker has occurred
     * @param containerName
     * @return id of created container or null if it wasn't created
     */
    internal fun createWithFile(runConfiguration: RunConfiguration,
                                containerName: String,
                                file: File,
                                resources: Collection<File> = emptySet()): String {}
```

## Environment information
* diktat version: 0.4.0

### Additional contract requirements

- When autofixing basic KDoc tags, place `@param` tags before `@return`, and place `@return` before `@throws` tags.
- Autofixing basic KDoc tags must preserve every existing tag occurrence and its content.
