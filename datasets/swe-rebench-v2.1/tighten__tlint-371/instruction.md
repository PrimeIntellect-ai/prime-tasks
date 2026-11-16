Add option to ignore excaped braces for SpacesAroundBladeRenderContent
I'm rendering available placeholders into blade using the following, escaping blade's processing via [the documented method](https://laravel.com/docs/11.x/blade#blade-and-javascript-frameworks):
```html
Placeholders:
<ul>
    <li><code>@@{{PROJECT_MANAGER_NAME}}</code>: The name of the project manager.</li>
</ul>
```

Which gives me, this:
![image](https://github.com/user-attachments/assets/6c24be3b-c38c-46b9-9445-94806b7ba35e)

This is all good until tlint thows the error `Spaces around blade rendered content`.

Is it possible to configure the *SpacesAroundBladeRenderContent* rule to ignore escaped braces?
