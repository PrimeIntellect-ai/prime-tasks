Update SeleniumLibrary is_truthy and is_falsy to follow Robot Framework 3.1
In Robot Framework `is_truthy` and `is_falsy` has changed between 3.0 and 3.1 version. In Robot Framewrok 3.1 string `0` is considered `False`, but in 3.0 string `0` is `True`. Same also applies to string `off`. Change SeleniumLibrary `is_truthy` and `is_falsy` to follow RF 3.1.

Reference  #1304
