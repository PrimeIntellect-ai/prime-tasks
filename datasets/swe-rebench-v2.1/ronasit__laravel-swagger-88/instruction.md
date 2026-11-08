Function () does not exist
I'm using https://github.com/laravel-json-api/laravel and this is what happens when I get the tests with laravel-swagger installed:

```  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   FAILED  Api\V0\Orders\ReadTest >
  Failed asserting that the HTTP status 500 is 200. The response errors were:
{
    "errors": [
        {
            "detail": "Function () does not exist",
            "meta": {
                "exception": "ReflectionException",
                "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                "line": 49,
                "trace": [
                    {
                        "class": "ReflectionFunction",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                        "function": "__construct",
                        "line": 49,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                        "function": "getClassByInterface",
                        "line": 40,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                        "function": "transformDependency",
                        "line": 28,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "function": "RonasIT\\Support\\AutoDoc\\Traits\\{closure}",
                        "type": "->"
                    },
                    {
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                        "function": "array_map",
                        "line": 27
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php",
                        "function": "getDependencies",
                        "line": 20,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php",
                        "function": "resolveClassMethodDependencies",
                        "line": 489,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php",
                        "function": "getConcreteRequest",
                        "line": 249,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php",
                        "function": "parseRequest",
                        "line": 183,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Services\\SwaggerService",
                        "file": "/var/www/html/vendor/ronasit/laravel-swagger/src/Http/Middleware/AutoDocMiddleware.php",
                        "function": "addData",
                        "line": 20,
                        "type": "->"
                    },
                    {
                        "class": "RonasIT\\Support\\AutoDoc\\Http\\Middleware\\AutoDocMiddleware",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/SubstituteBindings.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 50,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Middleware\\SubstituteBindings",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 152,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Middleware\\ThrottleRequests",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php",
                        "function": "handleRequest",
                        "line": 118,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Middleware\\ThrottleRequests",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php",
                        "function": "handleRequestUsingNamedLimiter",
                        "line": 80,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Middleware\\ThrottleRequests",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 116,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php",
                        "function": "then",
                        "line": 797,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Router",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php",
                        "function": "runRouteWithinStack",
                        "line": 776,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Router",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php",
                        "function": "runRoute",
                        "line": 740,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Router",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php",
                        "function": "dispatchToRoute",
                        "line": 729,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Routing\\Router",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php",
                        "function": "dispatch",
                        "line": 200,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Kernel",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "Illuminate\\Foundation\\Http\\{closure}",
                        "line": 141,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/barryvdh/laravel-debugbar/src/Middleware/InjectDebugbar.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 59,
                        "type": "->"
                    },
                    {
                        "class": "Barryvdh\\Debugbar\\Middleware\\InjectDebugbar",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TransformsRequest.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 21,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\TransformsRequest",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/ConvertEmptyStringsToNull.php",
                        "function": "handle",
                        "line": 31,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\ConvertEmptyStringsToNull",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TransformsRequest.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 21,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\TransformsRequest",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TrimStrings.php",
                        "function": "handle",
                        "line": 40,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\TrimStrings",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/ValidatePostSize.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 27,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\ValidatePostSize",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/PreventRequestsDuringMaintenance.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 86,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Middleware\\PreventRequestsDuringMaintenance",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Http/Middleware/HandleCors.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 62,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Http\\Middleware\\HandleCors",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Http/Middleware/TrustProxies.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 39,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Http\\Middleware\\TrustProxies",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "handle",
                        "line": 180,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php",
                        "function": "Illuminate\\Pipeline\\{closure}",
                        "line": 116,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Pipeline\\Pipeline",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php",
                        "function": "then",
                        "line": 175,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Kernel",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php",
                        "function": "sendRequestThroughRouter",
                        "line": 144,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Http\\Kernel",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/Concerns/MakesHttpRequests.php",
                        "function": "handle",
                        "line": 563,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Testing\\TestCase",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/Concerns/MakesHttpRequests.php",
                        "function": "call",
                        "line": 529,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Testing\\TestCase",
                        "file": "/var/www/html/vendor/laravel-json-api/testing/src/TestBuilder.php",
                        "function": "json",
                        "line": 387,
                        "type": "->"
                    },
                    {
                        "class": "LaravelJsonApi\\Testing\\TestBuilder",
                        "file": "/var/www/html/vendor/laravel-json-api/testing/src/TestBuilder.php",
                        "function": "call",
                        "line": 313,
                        "type": "->"
                    },
                    {
                        "class": "LaravelJsonApi\\Testing\\TestBuilder",
                        "file": "/var/www/html/tests/Feature/Api/V0/Orders/ReadTest.php",
                        "function": "get",
                        "line": 49,
                        "type": "->"
                    },
                    {
                        "class": "Api\\V0\\Orders\\ReadTest",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php",
                        "function": "test",
                        "line": 1065,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestCase",
                        "file": "/var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/TestCase.php",
                        "function": "runTest",
                        "line": 174,
                        "type": "->"
                    },
                    {
                        "class": "Illuminate\\Foundation\\Testing\\TestCase",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php",
                        "function": "runTest",
                        "line": 632,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestCase",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestRunner.php",
                        "function": "runBare",
                        "line": 101,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestRunner",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php",
                        "function": "run",
                        "line": 468,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestCase",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php",
                        "function": "run",
                        "line": 357,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestSuite",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php",
                        "function": "run",
                        "line": 357,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestSuite",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php",
                        "function": "run",
                        "line": 357,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\Framework\\TestSuite",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/TextUI/TestRunner.php",
                        "function": "run",
                        "line": 63,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\TextUI\\TestRunner",
                        "file": "/var/www/html/vendor/phpunit/phpunit/src/TextUI/Application.php",
                        "function": "run",
                        "line": 168,
                        "type": "->"
                    },
                    {
                        "class": "PHPUnit\\TextUI\\Application",
                        "file": "/var/www/html/vendor/phpunit/phpunit/phpunit",
                        "function": "run",
                        "line": 99,
                        "type": "->"
                    }
                ]
            },
            "status": "500",
            "title": "Internal Server Error"
        }
    ],
    "jsonapi": {
        "version": "1.0"
    }
}.

The following exception occurred during the last request:

ReflectionException: Function () does not exist in /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php:49
Stack trace:
#0 /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php(49): ReflectionFunction->__construct()
#1 /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php(40): RonasIT\Support\AutoDoc\Services\SwaggerService->getClassByInterface()
#2 /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php(28): RonasIT\Support\AutoDoc\Services\SwaggerService->transformDependency()
#3 [internal function]: RonasIT\Support\AutoDoc\Services\SwaggerService->RonasIT\Support\AutoDoc\Traits\{closure}()
#4 /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php(27): array_map()
#5 /var/www/html/vendor/ronasit/laravel-swagger/src/Traits/GetDependenciesTrait.php(20): RonasIT\Support\AutoDoc\Services\SwaggerService->getDependencies()
#6 /var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php(489): RonasIT\Support\AutoDoc\Services\SwaggerService->resolveClassMethodDependencies()
#7 /var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php(249): RonasIT\Support\AutoDoc\Services\SwaggerService->getConcreteRequest()
#8 /var/www/html/vendor/ronasit/laravel-swagger/src/Services/SwaggerService.php(183): RonasIT\Support\AutoDoc\Services\SwaggerService->parseRequest()
#9 /var/www/html/vendor/ronasit/laravel-swagger/src/Http/Middleware/AutoDocMiddleware.php(20): RonasIT\Support\AutoDoc\Services\SwaggerService->addData()
#10 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): RonasIT\Support\AutoDoc\Http\Middleware\AutoDocMiddleware->handle()
#11 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/SubstituteBindings.php(50): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#12 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Routing\Middleware\SubstituteBindings->handle()
#13 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php(152): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#14 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php(118): Illuminate\Routing\Middleware\ThrottleRequests->handleRequest()
#15 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Middleware/ThrottleRequests.php(80): Illuminate\Routing\Middleware\ThrottleRequests->handleRequestUsingNamedLimiter()
#16 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Routing\Middleware\ThrottleRequests->handle()
#17 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(116): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#18 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php(797): Illuminate\Pipeline\Pipeline->then()
#19 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php(776): Illuminate\Routing\Router->runRouteWithinStack()
#20 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php(740): Illuminate\Routing\Router->runRoute()
#21 /var/www/html/vendor/laravel/framework/src/Illuminate/Routing/Router.php(729): Illuminate\Routing\Router->dispatchToRoute()
#22 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php(200): Illuminate\Routing\Router->dispatch()
#23 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(141): Illuminate\Foundation\Http\Kernel->Illuminate\Foundation\Http\{closure}()
#24 /var/www/html/vendor/barryvdh/laravel-debugbar/src/Middleware/InjectDebugbar.php(59): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#25 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Barryvdh\Debugbar\Middleware\InjectDebugbar->handle()
#26 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TransformsRequest.php(21): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#27 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/ConvertEmptyStringsToNull.php(31): Illuminate\Foundation\Http\Middleware\TransformsRequest->handle()
#28 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Foundation\Http\Middleware\ConvertEmptyStringsToNull->handle()
#29 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TransformsRequest.php(21): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#30 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/TrimStrings.php(40): Illuminate\Foundation\Http\Middleware\TransformsRequest->handle()
#31 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Foundation\Http\Middleware\TrimStrings->handle()
#32 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/ValidatePostSize.php(27): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#33 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Foundation\Http\Middleware\ValidatePostSize->handle()
#34 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Middleware/PreventRequestsDuringMaintenance.php(86): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#35 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Foundation\Http\Middleware\PreventRequestsDuringMaintenance->handle()
#36 /var/www/html/vendor/laravel/framework/src/Illuminate/Http/Middleware/HandleCors.php(62): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#37 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Http\Middleware\HandleCors->handle()
#38 /var/www/html/vendor/laravel/framework/src/Illuminate/Http/Middleware/TrustProxies.php(39): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#39 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(180): Illuminate\Http\Middleware\TrustProxies->handle()
#40 /var/www/html/vendor/laravel/framework/src/Illuminate/Pipeline/Pipeline.php(116): Illuminate\Pipeline\Pipeline->Illuminate\Pipeline\{closure}()
#41 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php(175): Illuminate\Pipeline\Pipeline->then()
#42 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php(144): Illuminate\Foundation\Http\Kernel->sendRequestThroughRouter()
#43 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/Concerns/MakesHttpRequests.php(563): Illuminate\Foundation\Http\Kernel->handle()
#44 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/Concerns/MakesHttpRequests.php(529): Illuminate\Foundation\Testing\TestCase->call()
#45 /var/www/html/vendor/laravel-json-api/testing/src/TestBuilder.php(387): Illuminate\Foundation\Testing\TestCase->json()
#46 /var/www/html/vendor/laravel-json-api/testing/src/TestBuilder.php(313): LaravelJsonApi\Testing\TestBuilder->call()
#47 /var/www/html/tests/Feature/Api/V0/Orders/ReadTest.php(49): LaravelJsonApi\Testing\TestBuilder->get()
#48 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php(1065): Api\V0\Orders\ReadTest->test()
#49 /var/www/html/vendor/laravel/framework/src/Illuminate/Foundation/Testing/TestCase.php(174): PHPUnit\Framework\TestCase->runTest()
#50 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php(632): Illuminate\Foundation\Testing\TestCase->runTest()
#51 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestRunner.php(101): PHPUnit\Framework\TestCase->runBare()
#52 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestCase.php(468): PHPUnit\Framework\TestRunner->run()
#53 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php(357): PHPUnit\Framework\TestCase->run()
#54 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php(357): PHPUnit\Framework\TestSuite->run()
#55 /var/www/html/vendor/phpunit/phpunit/src/Framework/TestSuite.php(357): PHPUnit\Framework\TestSuite->run()
#56 /var/www/html/vendor/phpunit/phpunit/src/TextUI/TestRunner.php(63): PHPUnit\Framework\TestSuite->run()
#57 /var/www/html/vendor/phpunit/phpunit/src/TextUI/Application.php(168): PHPUnit\TextUI\TestRunner->run()
#58 /var/www/html/vendor/phpunit/phpunit/phpunit(99): PHPUnit\TextUI\Application->run()
#59 {main}

----------------------------------------------------------------------------------

Function () does not exist

  at vendor/cloudcreativity/json-api-testing/src/HttpAssert.php:65
     61▕         string $content = null,
     62▕         string $message = ''
     63▕     ): void
     64▕     {
  ➜  65▕         PHPUnitAssert::assertThat(
     66▕             $status,
     67▕             new HttpStatusIs($expected, $content),
     68▕             $message
     69▕         );

      +4 vendor frames
  5   tests/Feature/Api/V0/Orders/ReadTest.php:51
```

Any suggestions? Thank you.
