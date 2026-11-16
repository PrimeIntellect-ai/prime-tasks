V3 forced all RequestInfo not null
V2.3.5 allows nullable RequestInfo for Put, Patch and Post.
However, this change force all not null https://github.com/bkbnio/kompendium/pull/256.

From

```
data class PutInfo<TParam, TReq, TResp>(
  [HIDDEN]
  override val responseInfo: ResponseInfo<TResp>,
  override val summary: String,
  override val description: String? = null,
  override val tags: Set<String> = emptySet(),
  override val deprecated: Boolean = false,
  override val securitySchemes: Set<String> = emptySet(),
  override val canThrow: Set<ExceptionInfo<*>> = emptySet(),
  override val parameterExamples: Set<ParameterExample> = emptySet(),
  override val operationId: String? = null
) : MethodInfo<TParam, TResp>
```
to ( newest code)

```
class PutInfo private constructor(
  [HIDDEN]
  override val errors: MutableList<ResponseInfo>,
  override val response: ResponseInfo,
  override val tags: Set<String>,
  override val summary: String,
  override val description: String,
  override val externalDocumentation: ExternalDocumentation?,
  override val operationId: String?,
  override val deprecated: Boolean,
  override val parameters: List<Parameter>
) : MethodInfoWithRequest {

  companion object {
    fun builder(init: Builder.() -> Unit): PutInfo {
      val builder = Builder()
      builder.init()
      return builder.build()
    }
  }

  class Builder : MethodInfoWithRequest.Builder<PutInfo>() {
    override fun build() = PutInfo(
      [HIDDEN]
      errors = errors,
      response = response ?: error("response info must be present"),
      tags = tags,
      summary = summary ?: error("Summary must be present"),
      description = description ?: error("Description must be present"),
      externalDocumentation = externalDocumentation,
      operationId = operationId,
      deprecated = deprecated,
      parameters = parameters
    )
  }
}
```

Can you help to make them nullable back? (A similar request here https://github.com/bkbnio/kompendium/issues/242)

### Additional contract requirements

- POST, PUT, and PATCH operations must be constructible without request metadata. When request metadata is absent, the generated OpenAPI operation must omit the request body.
