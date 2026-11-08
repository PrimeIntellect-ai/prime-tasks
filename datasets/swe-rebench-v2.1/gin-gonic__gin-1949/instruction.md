how to binding for multi files upload
#1263's merged solution take no effect for multi files uploading.

my code:
```go
// MailUpload struct for e-mail
type MailUpload struct {
	Mail string 			     `json:"mail" form:"mail" binding:"required"`
	Attachments  []*multipart.FileHeader `json:"attachment,omitempty" form:"attachments" binding:"required"` // change form to "attachments[]" take no effect also.
}

func Mail(c *gin.Context) {
	var postData MailUpload
	err := c.Bind(&postData)
	if err != nil {
		fmt.Println(err)
		c.String(http.StatusBadRequest, err.Error())
	} else {
		fmt.Printf("%#v\n", postData)
		c.String(http.StatusOK, "ok")
	}
}
```

request send command by curl:
```bash
curl -v -H "Content-Type:multipart/form-data" -X POST http://localhost:8080/api/latest/newmail -F "attachments[]=@./2019-5-1_day_trends.png" -F mail=123
```

my error: `Key: 'MailUpload.Attachments' Error:Field validation for 'Attachments' failed on the 'required' tag`

### Additional contract requirements

- Multipart form binding is exposed as the exported value `FormMultipart` in package `binding` (import path `github.com/gin-gonic/gin/binding`). Its method `Bind(req *http.Request, obj interface{}) error` binds the request multipart form data into `obj`, returning `nil` on success and a non-nil error otherwise.
- `obj` is a pointer to a struct whose exported fields are tagged `form:"<key>"`; a field is populated from the uploaded files whose form field name equals `<key>`. The supported field types are `multipart.FileHeader`, `*multipart.FileHeader`, `[]multipart.FileHeader`, `[]*multipart.FileHeader`, and fixed-size arrays `[N]multipart.FileHeader` and `[N]*multipart.FileHeader`.
- A slice field receives all uploaded files for its key.
- For a fixed-size array field, the array length must equal the number of uploaded files for its key; otherwise binding returns an error.
- Binding returns an error when a field type is not one of the supported types.
- A field tagged `binding:"required"` is validated: binding returns an error when no file is uploaded for its key, and succeeds when the required file(s) are present.
