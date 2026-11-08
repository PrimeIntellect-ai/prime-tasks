Map lookup operator (?) is type to return a map, causing an error when multiplying it
For example, the query `random-number-generator()?next * 100`  causes an error. While it should just work.

Repro:
 https://xpath.playground.fontoxml.com/?state=H4sIACEO0GIAA6tWys1PSVWyMtBRKkssykxMykktVrJSqq5V0lGqyM0BMm2AlIK%2BHYgfWJpaVAkU0ihKzEvJz9XNK81NSi3STU%2FNSy1KLMkv0tC0hwhpKmgpGBoAtSTn55WkVpTANCrVAgCbm7mncAAAAA%3D%3D
