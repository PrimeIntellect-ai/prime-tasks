Shebang directive on top of the file breaks #r SDK parsing
In the Specifying an sdk u show an example creating a web app:

#r "sdk:Microsoft.NET.Sdk.Web"

using Microsoft.AspNetCore.Builder;

var a = WebApplication.Create();
a.MapGet("/", () => "Hello world");
a.Run();

====

I get error  saying 'AspNetCore' does not exist in namespace 'Microsoft'.

Has this changed?

environment:
Mac osx ARM
i have Core6 and Core7 Frameworks installed. Currently using Core7.

I created project using command as shown in doc $> dotnet script init

thx ~Marvin Foster
mmarvb7@gmail.com or marvinfoster@finsync.com
