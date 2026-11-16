The CreateEditImage API should have an optional Mask parameter.
In image.go func CreateEditImage,
Mask is required in current implementation:
[HIDDEN]
But it is optional in official docs:
https://platform.openai.com/docs/api-reference/images/create-edit
/*
mask
string
Optional
An additional image whose fully transparent areas (e.g. where alpha is zero) indicate where image should be edited. Must be a valid PNG file, less than 4MB, and have the same dimensions as image.
*/
