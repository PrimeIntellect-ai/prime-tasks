belongsToMany Foreign UUID not working.
- Laravel Version: 10.10
- PHP Version: 8.1
- Blueprint Version: 2.9
- Platform: Windows

### Issue:
The pivot table on a belongsToMany is not respecting UUID from the related models. Should be **foreignUuid**

![image](https://github.com/laravel-shift/blueprint/assets/1649159/b5585a6c-358b-4bd9-ba4e-551c11845932)


### draft.yaml:
```
models:
  Brand:
    uuid
    name: string index
    slug: string unique index
    logo: string nullable
    softDeletes
    relationships:
      belongsToMany: Product
  Product:
    uuid
    name: string index
    slug: unique index
    price: double:8,2
    softDeletes
    relationships:
      belongsToMany: Brand
```
