Schema Property with only additionalProperties schema defined
We encountered an issue for when a schema property is defined with only the **type** and **additionalProperties** with the schema defined under that key.

The API we're retrieving the OpenAPI swagger spec from does this to allow a map[string]struct with the struct being the **additionalProperties**. The example below shows the schema we're working with and the problem occurs with the **relationships** schema.

```yaml
    WritableCircuitTerminationRequest:
      type: object
      description: |-
        Base class to use for serializers based on OrganizationalModel or PrimaryModel.

        Can also be used for models derived from BaseModel, so long as they support custom fields and relationships.
      properties:
        circuit:
          type: string
          format: uuid
        site:
          type: string
          format: uuid
          nullable: true
        location:
          type: string
          format: uuid
          nullable: true
        provider_network:
          type: string
          format: uuid
          nullable: true
        description:
          type: string
          maxLength: 200
        custom_fields:
          type: object
          additionalProperties: {}
        relationships:
          type: object
          additionalProperties:
            type: object
            required:
              - id
              - url
              - name
              - type
            properties:
              id:
                type: string
                format: uuid
                readOnly: true
              url:
                type: string
                format: uri
                readOnly: true
              name:
                type: string
                readOnly: true
              type:
                type: string
                readOnly: true
                example: one-to-many
              source:
                type: object
                properties:
                  label:
                    type: string
                    readOnly: true
                  object_type:
                    type: string
                    readOnly: true
                    example: dcim.site
                  objects:
                    type: array
                    items:
                      type: object
                      properties:
                        id:
                          type: string
                          format: uuid
                        url:
                          type: string
                          format: uri
                          readOnly: true
                        display:
                          type: string
                          readOnly: true
                      additionalProperties: true
              destination:
                type: object
                properties:
                  label:
                    type: string
                    readOnly: true
                  object_type:
                    type: string
                    readOnly: true
                    example: dcim.site
                  objects:
                    type: array
                    items:
                      type: object
                      properties:
                        id:
                          type: string
                          format: uuid
                        url:
                          type: string
                          format: uri
                          readOnly: true
                        display:
                          type: string
                          readOnly: true
                      additionalProperties: true
              peer:
                type: object
                properties:
                  label:
                    type: string
                    readOnly: true
                  object_type:
                    type: string
                    readOnly: true
                    example: dcim.site
                  objects:
                    type: array
                    items:
                      type: object
                      properties:
                        id:
                          type: string
                          format: uuid
                        url:
                          type: string
                          format: uri
                          readOnly: true
                        display:
                          type: string
                          readOnly: true
                      additionalProperties: true
      required:
        - circuit
```

When generating the types for the schema, it implies it there should be a new type, but forgoes the creation of that type. Below is the code generated.

```go
type BulkWritableCircuitTerminationRequest struct {
	// Circuit Returns a nested representation of an object on read, but accepts either the nested representation or the
	// primary key value on write operations.
	Circuit         NestedCircuitRequest          `json:"circuit"`
	CustomFields    *map[string]interface{}       `json:"custom_fields,omitempty"`
	Description     *string                       `json:"description,omitempty"`
	Id              openapi_types.UUID            `json:"id"`
	Location        *NestedLocationRequest        `json:"location"`
	PortSpeed       *int                          `json:"port_speed"`
	PpInfo          *string                       `json:"pp_info,omitempty"`
	ProviderNetwork *NestedProviderNetworkRequest `json:"provider_network"`
	Relationships   *map[string]struct {
		Destination *struct {
			Label      *string                                                                         `json:"label,omitempty"`
			ObjectType *string                                                                         `json:"object_type,omitempty"`
			Objects    *[]BulkWritableCircuitTerminationRequest_Relationships_Destination_Objects_Item `json:"objects,omitempty"`
		} `json:"destination,omitempty"`
		Id   *openapi_types.UUID `json:"id,omitempty"`
		Name *string             `json:"name,omitempty"`
		Peer *struct {
			Label      *string                                                                  `json:"label,omitempty"`
			ObjectType *string                                                                  `json:"object_type,omitempty"`
			Objects    *[]BulkWritableCircuitTerminationRequest_Relationships_Peer_Objects_Item `json:"objects,omitempty"`
		} `json:"peer,omitempty"`
		Source *struct {
			Label      *string                                                                    `json:"label,omitempty"`
			ObjectType *string                                                                    `json:"object_type,omitempty"`
			Objects    *[]BulkWritableCircuitTerminationRequest_Relationships_Source_Objects_Item `json:"objects,omitempty"`
		} `json:"source,omitempty"`
		Type *string `json:"type,omitempty"`
		Url  *string `json:"url,omitempty"`
	} `json:"relationships,omitempty"`
```

It shows that there should be three additional types created but never creates them:

- BulkWritableCircuitTerminationRequest_Relationships_Destination_Objects_Item
- BulkWritableCircuitTerminationRequest_Relationships_Peer_Objects_Item
- BulkWritableCircuitTerminationRequest_Relationships_Source_Objects_Item

### Additional contract requirements

The nested item type definitions must be generated for every schema that uses this pattern, not only for `BulkWritableCircuitTerminationRequest`. For each of the schemas `WritableCircuitTerminationRequest`, `BulkWritableCircuitTerminationRequest`, and `PatchedBulkWritableCircuitTerminationRequest`, the generator must emit a distinct struct type for the `objects` array items of each of the `destination`, `peer`, and `source` relationship objects. The required type names are:

- `<SchemaName>_Relationships_Destination_Objects_Item`
- `<SchemaName>_Relationships_Peer_Objects_Item`
- `<SchemaName>_Relationships_Source_Objects_Item`

where `<SchemaName>` is one of the three schema names above. Each such type must be declared as a struct and used as the element type of the corresponding `objects` array field.
