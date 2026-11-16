Automatic casting of nested array DTOs doesn't work with DataTransferObjectCollection
```php
class TagData extends DataTransferObject
{
   public string $name;
}

class TagDataCollection extends DataTransferObjectCollection
{
    public function current(): TagData
    {
        return parent::current();
    }
}

class PostData extends DataTransferObject
{
   public TagDataCollection $tags;
}

$postData = new PostData([
    'tags' => [
        ['name' => 'foo'],
        ['name' => 'bar']
    ]
]);
```

Would you be open for a PR?
