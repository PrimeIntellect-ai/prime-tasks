uuid shorthand generates a relationship in the model
<!-- PLEASE COMPLETE THIS TEMPLATE -->

- Laravel Version: 8.17.2
- PHP Version: 7.14.3
- Blueprint Version: 1.19.2
- Platform: Mac

### Issue:

The model generates a uuid relationship see generated code as below

`<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AgeCohort extends Model
{
    use HasFactory;

    /**
     * The attributes that are mass assignable.
     *
     * @var array
     */
    protected $fillable = [
        'name',
        'description',
        'min_age',
        'max_age',
        'uuid',
    ];

    /**
     * The attributes that should be cast to native types.
     *
     * @var array
     */
    protected $casts = [
        'id' => 'integer',
    ];


    public function uuid()
    {
        return $this->belongsTo(\App\Models\Uuid::class);
    }
}
`

### draft.yaml:
```yaml
models:
  AgeCohort:
    id
    timestamps
    name: string:100
    description: string:500 nullable
    min_age: integer nullable
    max_age: integer nullable
    uuid: uuid unique
```
