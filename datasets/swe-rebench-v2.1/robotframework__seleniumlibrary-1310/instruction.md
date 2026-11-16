Get Cookies keyword will fail if the Selenium get_cookie method return value contains more keys than: name, value, path, domain, secure, httpOnly and expiry
Selenium [get_cookie](https://seleniumhq.github.io/selenium/docs/api/py/webdriver_remote/selenium.webdriver.remote.webdriver.html?highlight=get_cookie#selenium.webdriver.remote.webdriver.WebDriver.get_cookie) returns a dictionary. If the dictionary contains more keys then the `name`, `value`, `path`, `domain`, `secure`, `httpOnly` and `expiry`, then the Get Cookies keyword will fail:
```
20190212 16:54:43.113 :  FAIL : TypeError: __init__() got an unexpected keyword argument 'hCode'
20190212 16:54:43.113 : DEBUG :
Traceback (most recent call last):
  File "C:\Python27\lib\site-packages\SeleniumLibrary\__init__.py", line 369, in run_keyword
    return DynamicCore.run_keyword(self, name, args, kwargs)
  File "C:\Python27\lib\site-packages\SeleniumLibrary\base\robotlibcore.py", line 102, in run_keyword
    return self.keywords[name](*args, **kwargs)
  File "C:\Python27\lib\site-packages\SeleniumLibrary\keywords\cookie.py", line 99, in get_cookie
    return CookieInformation(**cookie)
```
This is because the Get Cookies keywords has hard coded keys what Selenium response [can contain in the CookieInformation](https://github.com/robotframework/SeleniumLibrary/blob/master/src/SeleniumLibrary/keywords/cookie.py#L152) object. The limitation has been in place since the SeleniumLibrary 3.0 release, but there was issue reported in Slack, that for that particular user, Selenium `get_cookie` did return the following:
```
{u'domain': u'1.2.3.4', u'name': u'components_state', u'value': u'alsdjaslkdjasdlkj', u'path': u'/', u'hCode': -1693023704, u'class': u'org.openqa.selenium.Cookie', u'httpOnly': False, u'secure': False}
```
SeleniumLibrary should not fail, if the Selenium `get_cookie`  returns more keys that [is specified ](https://w3c.github.io/webdriver/#dfn-table-for-cookie-conversion). Instead we should allow extra keys to be passed to the `CookieInformation` object and allow access to the extra keys in similar way as the specified keys.
