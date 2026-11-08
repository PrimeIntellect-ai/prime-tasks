RemovedInDjango41Warning: 'django_extensions' defines default_app_config
The following warning is emitted when using django-extenstions along with django 3.2
```
django.utils.deprecation.RemovedInDjango41Warning: 'django_extensions' defines default_app_config = 'django_extensions.apps.DjangoExtensionsConfig'. Django now detects this configuration automatically. You can remove default_app_config.
```

I suppose it is related to the change introduced by django 3.2: https://docs.djangoproject.com/en/3.2/releases/3.2/#what-s-new-in-django-3-2

Environment:
* python 3.8
* django 3.2
