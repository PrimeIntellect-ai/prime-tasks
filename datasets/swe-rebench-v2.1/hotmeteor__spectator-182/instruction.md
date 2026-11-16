Request body required for file uploads in Laravel tests
Hello! My case is following for uploading single file in Laravel tests. Error first:

```
ErrorException: Request body required.
Failed asserting that true is false.
/var/www/html/vendor/laravel/framework/src/Illuminate/Macroable/Traits/Macroable.php:123
/var/www/html/vendor/laravel/framework/src/Illuminate/Testing/TestResponse.php:1753
/var/www/html/vendor/hotmeteor/spectator/src/Assertions.php:26
/var/www/html/vendor/laravel/framework/src/Illuminate/Macroable/Traits/Macroable.php:123
/var/www/html/vendor/laravel/framework/src/Illuminate/Testing/TestResponse.php:1753
/var/www/html/tests/Feature/Assignment/AssignmentUploadTest.php:58
/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/TestCase.php:174
```

 I defined Swagger as follows:

```
<?php

namespace App\Swagger\Actions\Assignment;

use OpenApi\Annotations as OA;

/**
 * @OA\Post(
 *     path="/excel/upload",
 *     summary="Upload Excel (XLSX) file with assignments",
 *     tags={"assignments"},
 *     security={{"bearerAuth": {}}},
 *
 *     @OA\RequestBody(
 *         required=true,
 *         description="Uploads Excel file with assignments",
 *         @OA\MediaType(
 *             mediaType="multipart/form-data",
 *             @OA\Schema(
 *                 @OA\Property(property="file", type="string", format="binary"),
 *             )
 *         )
 *     ),
 *
 *     @OA\Response(
 *         response=204,
 *         description="Success message"
 *     ),
 *
 *     @OA\Response(response=401, description="Unauthorized"),
 *     @OA\Response(response=403, description="Forbidden"),
 * )
 */
class Upload
{
}
```

Test in Laravel looks more or less like this:

```
public function testValidUploadWithFile(): void
{
    $file = UploadedFile::fake()->create('test_file.xlsx', $this->contentFile);
    $response = $this->actingAs(User::factory()->admin()->create(), 'sanctum')
        ->post(route('excel.upload'), ['file' => $file]);

    $response
        ->assertValidRequest() // TODO: Fix Swagger's Upload.php to define multipart/form-data as we get here "ErrorException: Request body required."
        ->assertValidResponse(204); // It works
}
```

And I get this error I mentioned at the beginning. Isn't it some incorrect validation in Spectator? I think Laravel builds multipart request for this, but I get `ErrorException: Request body required.`

### Additional contract requirements

An OpenAPI request body marked as required must still be rejected when the parsed request body is absent or empty.
