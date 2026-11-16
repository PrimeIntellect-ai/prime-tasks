Changing Default Class Namespace to "App" is getting error in livewire.php config
### Description
I want to change the Default Livewire Directory from `"App\\Http\\Livewire" ` to "App" but it is getting error

### Exact steps to reproduce
Go to livewire.php in config folder.
Change the default value of class_namespace to "App"
and execute the command below

`php artisan livewire:discover`

and this error will show

The "C:\laragon\www\my_project\app/App" directory does not exist.

if I change it to null or empty string, the generated class namespace will also be

`namespace \Component\Component;`


any work around for this? Thank you.

**Context**
- Livewire version: [e.g. 2.3.1]
- Laravel version: [e.g. 8.3.1]
- Browser: [MS Edge]
