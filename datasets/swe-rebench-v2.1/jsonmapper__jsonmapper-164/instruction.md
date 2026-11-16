Starting with v2.15.0 constructor for nested array of objects is not called
**Describe the bug**
Starting with v2.15.0 constructor for nested array of objects is not called.

**To Reproduce**
Steps to reproduce the behaviour:
I have a case like this:
```
class Article
{
    /** @var Tag[] */
    public array $tags;
}

class Tag
{
    private $configuration;

    public function __construct()
    {
        $this->configuration = Config::get('myconfiguration');
    }
}

// Usage
$mapper = (new JsonMapperFactory())->bestFit();
$result = $mapper->mapArray($jsonData, new Article());
```
Up until v2.14.4 everything works as expected - the constructor is called.
Starting with v2.15.0 the constructor is not called anymore and I get an issue because of the non-initialised/empty `$configuration`.

Here is a comparison between the two versions: https://github.com/JsonMapper/JsonMapper/compare/2.14.4...2.15.0

**Expected behavior**
The constructor for the `Tag` gets called.

**Environment (please complete the following information):**
 - PHP: 8.2.5

**Additional context**
Add any other context about the problem here.

**UPDATE**
I have prepared a test case and example with results.

```
class TestArticle
{
    public int $id;
    public string $title;

    /** @var TestTag[] */
    public array $tags;
}

class TestTag
{
    private string $configuration;

    public int $id;
    public string $name;

    public function __construct()
    {
        $this->configuration = "Works?";
    }
}

class Test
{
    public function test()
    {
        $data = json_decode('[{"id":1,"title":"Article 1","tags":[{"id":1,"name":"Tag 1"},{"id":2,"name":"Tag 2"}]},{"id":2,"title":"Article 2","tags":[{"id":1,"name":"Tag 1"},{"id":3,"name":"Tag 3"}]}]');
        $mapper = (new JsonMapperFactory())->bestFit();
        return $mapper->mapArray($data, new TestArticle());
    }
}

$test = new Test();
dd($test->test());
```

Here is a comparison of the results with v2.14.4 and v2.15.0.
| 2.14.4  | 2.15.0 |
| ------------- | ------------- |
| <img width="341" alt="Screenshot 2023-05-25 at 13 04 42" src="https://github.com/JsonMapper/JsonMapper/assets/934385/e599595f-c407-4aa3-8af7-65abbecdc225">  | <img width="292" alt="Screenshot 2023-05-25 at 13 05 16" src="https://github.com/JsonMapper/JsonMapper/assets/934385/7c641dc0-b542-40bd-b54f-0a52088ae89e">  |

As seen in the screenshots the `configuration` parameter is completely missing in the second screenshot.
