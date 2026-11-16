[Bug]mixed param and non-param paths
gin version 1.7.2

"/get/abc" = value1
"/get/:param" = value2

GET /get/abc => value1
GET /get/a => value2
GET /get/xyz => value2
GET /get/abcd => 404 (should be value2)
