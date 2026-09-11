# Conventions

## Project layout

```
EchoesIntegration/
  EchoesIntegration.csproj
  EchoesIntegration.Tests/
    EchoesIntegration.Tests.csproj
    GlobalUsings.cs
    Helpers/
      MockHttpMessageHandler.cs
    EchoesApiClientTests.cs
    EchoesAuthenticationTests.cs
    ...
```

Test project sits beside the production project, named `<Project>.Tests`. All six repos follow this.

Easypark additionally groups by production namespace (`Tests/Services/...`), which is worth copying
once you pass roughly ten test files. Below that it is overhead.

## The csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="Moq" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\EchoesIntegration.csproj" />
  </ItemGroup>

</Project>
```

**No `Version` attributes.** Echoes, Drive, Easypark and HubSpot use central package management --
versions live in a repo-root `Directory.Packages.props`:

```xml
<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
...
<PackageVersion Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
<PackageVersion Include="Moq" Version="4.20.72" />
<PackageVersion Include="xunit" Version="2.9.3" />
<PackageVersion Include="xunit.runner.visualstudio" Version="2.8.2" />
```

Those four versions are identical everywhere they are pinned. OFV is the exception: no
`Directory.Packages.props`, versions inline in the csproj -- at the same four versions, so it is a
divergence in mechanism, not in outcome. New repos should use central management.

`<Nullable>enable</Nullable>` in the test project matters. Without it the compiler stops warning
about the `null!` and `!` operators you scatter through test setup, and a genuinely null fixture
slips through.

## GlobalUsings.cs

```csharp
global using Xunit;
```

One line. Keeps `using Xunit;` out of 23 files. Do not push much further -- a global `using Moq;`
makes it non-obvious which tests use mocks at all.

## Loggers

```csharp
NullLogger<EchoesAccountClient>.Instance
```

from `Microsoft.Extensions.Logging.Abstractions`. No setup, no noise, no accidental assertions.

The estate is split -- 7 uses of `NullLogger<`, 10 of `Mock<ILogger`. Prefer `NullLogger` unless you
are asserting on log output, which nothing currently does. A `Mock<ILogger<T>>` that is never
verified is three lines of ceremony per test class for nothing.

## Options

```csharp
Options.Create(new EchoesOptions { AccountId = 2073, ApiKey = "k" })
```

Never `Mock<IOptions<T>>`. `Options.Create` is shorter and gives a real instance, so validation
attributes and computed properties behave as they do in production. That is what makes
`ApiKeyHeaderValue_AlwaysCarriesApikeyPrefix` a meaningful test.

## Test structure

`[Fact]` for a single case, `[Theory]` + `[InlineData]` when the same assertion runs over inputs:

```csharp
[Theory]
[InlineData("7b7cd938", "Apikey 7b7cd938")]
[InlineData("Apikey 7b7cd938", "Apikey 7b7cd938")]
[InlineData("apikey 7b7cd938", "apikey 7b7cd938")]
[InlineData("  7b7cd938  ", "Apikey 7b7cd938")]
public void ApiKeyHeaderValue_AlwaysCarriesApikeyPrefix(string configured, string expected)
```

The estate is 113 `[Fact]` to 4 `[Theory]`, which is under-using `[Theory]`. Four near-identical
`[Fact]`s that differ only in an input value should be one `[Theory]`.

Arrange/Act/Assert comments appear in 9 of 23 files. They are optional. Section dividers in a long
file are more useful:

```csharp
// ---------- Privacy key provider ----------
// ---------- Privacy key handler ----------
// ---------- Helpers ----------
```

## Helpers live at the bottom, private and static

```csharp
private static (EchoesPrivacyKeyProvider Provider, SequenceHandler Handler) CreateProvider(
    EchoesOptions options)
```

Returning a tuple of `(subject, handler)` lets a test assert on both without a field. Prefer this to
constructor-assigned fields when tests need different handler configurations -- fields force every
test in the class to share one setup.

## Hand-written stubs over Moq when you are counting

```csharp
private sealed class StubKeyProvider(params string[] keys) : IEchoesPrivacyKeyProvider
{
    private int _index;
    public int InvalidateCount { get; private set; }

    public Task<string> GetPrivacyKeyHeaderAsync(CancellationToken ct = default)
        => Task.FromResult(keys[Math.Min(_index, keys.Length - 1)]);

    public void Invalidate() { InvalidateCount++; _index++; }
}
```

This is clearer than the equivalent `Mock<IEchoesPrivacyKeyProvider>` with a `SetupSequence` and a
`Callback` incrementing a captured local, and it makes the state machine (returns key N, advances on
invalidate) readable in one place. Use primary constructors and `sealed`.

Use Moq when you want `Verify(...)` on an interface with many members. Use a stub when the fake has
behaviour.

## Running them

```powershell
dotnet test EchoesIntegration.Tests/EchoesIntegration.Tests.csproj
dotnet test --filter "FullyQualifiedName~EchoesAuthenticationTests"
```

And confirm CI actually runs them -- three of six repos do not:

```powershell
.\scripts\Check-PipelineTestEnforcement.ps1 -Path <repo>
```
