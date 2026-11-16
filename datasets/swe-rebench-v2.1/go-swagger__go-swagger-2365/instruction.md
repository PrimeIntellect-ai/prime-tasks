allOf is always pointer using inheritance
## Problem statement

Can't make allOf object to be not nullable. It's always pointer. `x-nullable:false` doesn't help.

## Swagger specification
```
BundleAttributesResponse:
    properties:
      type:
        $ref: "#/definitions/BundleType"
      items:
        description: Array of bundle items in the root of the bundle.
        type: array
        items:
          $ref: "#/definitions/BundleItemResponse"
      sections:
        description: Array of bundle section in the root of the bundle.
        type: array
        items:
          $ref: "#/definitions/ItemBundleSectionResponse"
BundleSectionResponse:
    type: object
    x-omitempty: false
    properties:
      id:
        type: string
        x-omitempty: false
        example: 5dfb977429ec145dd6f9c307
     ...
  ItemBundleSectionResponse:
    allOf:
      - $ref: "#/definitions/BundleSectionResponse"
      - type: object
        x-omitempty: false
        properties:
          items:
            description: Array of bundle items inside a section of the bundle
            type: array
            items:
              $ref: "#/definitions/BundleItemResponse"
```
## Go code:
### Actual
```
// BundleAttributesResponse bundle attributes response
//
// swagger:model BundleAttributesResponse
type BundleAttributesResponse struct {

	// Array of bundle items in the root of the bundle.
	Items []BundleItemResponse `json:"items"`

	// Array of bundle section in the root of the bundle.
	Sections []*ItemBundleSectionResponse `json:"sections"`

	// type
	Type BundleType `json:"type,omitempty"`
}
```
### Expected
```
// BundleAttributesResponse bundle attributes response
//
// swagger:model BundleAttributesResponse
type BundleAttributesResponse struct {

	// Array of bundle items in the root of the bundle.
	Items []BundleItemResponse `json:"items"`

	// Array of bundle section in the root of the bundle.
	Sections []ItemBundleSectionResponse `json:"sections"`

	// type
	Type BundleType `json:"type,omitempty"`
}
```
I need `Sections []ItemBundleSectionResponse` to be without pointer. Is it known issue or am i missing smth?
## Steps to reproduce
Run `swagger generate model --spec=swagger.yml`
## Environment
swagger version: v0.25.0
go version:  go1.13.5 linux/amd64
OS:  linux/amd64
