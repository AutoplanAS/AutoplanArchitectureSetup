# Faking Azure Storage

`TableServiceClient` and `TableClient` are concrete classes with virtual members, so Moq can fake
them. `AsyncPageable<T>` and `Page<T>` cannot be faked by Moq -- they are abstract classes with
abstract members that Moq cannot construct meaningfully. You have to subclass them by hand.

The complete worked example is
`EasyparkIntegration.Tests/Services/BillingRecordStorageServiceTests.cs` (380 lines, 6 tests).

## Setup

```csharp
public class BillingRecordStorageServiceTests
{
    private readonly Mock<TableServiceClient> _mockTableServiceClient;
    private readonly Mock<TableClient> _mockParkingRowsTable;
    private readonly Mock<TableClient> _mockOperatorLookupTable;
    private readonly TableBillingRecordStorageService _service;

    public BillingRecordStorageServiceTests()
    {
        _mockTableServiceClient = new Mock<TableServiceClient>();
        _mockParkingRowsTable = new Mock<TableClient>();
        _mockOperatorLookupTable = new Mock<TableClient>();

        _mockTableServiceClient
            .Setup(x => x.GetTableClient("EasyparkParkingRows"))
            .Returns(_mockParkingRowsTable.Object);

        _mockTableServiceClient
            .Setup(x => x.GetTableClient("EasyparkOperatorLookup"))
            .Returns(_mockOperatorLookupTable.Object);

        SetupOperatorLookup(Array.Empty<OperatorLookupEntity>());

        _service = new TableBillingRecordStorageService(
            _mockTableServiceClient.Object, _mockLogger.Object);
    }
```

Two things to copy:

- **`GetTableClient` is stubbed per table name.** If the service asks for a table you did not stub,
  Moq returns `null` and you get an NRE with no indication of which table. Stub every table the
  service touches.
- **A default empty lookup is configured in the constructor.** Tests that do not care about the
  lookup then do not have to set it up, and a test that forgets to does not fall through to a null
  `AsyncPageable`.

This requires the service to take `TableServiceClient` by injection. A service that news up its own
client from a connection string cannot be tested this way at all -- see
`autoplan-data-persistence/references/storage-clients.md`.

## Capturing what was written

`SubmitTransactionAsync` returns a value you rarely care about and receives the payload you always
care about. Use `.Callback` to capture, `.Returns` to satisfy the signature:

```csharp
private void SetupCaptureEntities(List<ParkingRowEntity> capturedEntities)
{
    _mockParkingRowsTable
        .Setup(x => x.SubmitTransactionAsync(
            It.IsAny<IEnumerable<TableTransactionAction>>(),
            It.IsAny<CancellationToken>()))
        .Callback<IEnumerable<TableTransactionAction>, CancellationToken>((actions, _) =>
        {
            foreach (var action in actions)
                if (action.Entity is ParkingRowEntity entity)
                    capturedEntities.Add(entity);
        })
        .Returns(Task.FromResult(Mock.Of<Azure.Response<IReadOnlyList<Azure.Response>>>()));
}
```

`Mock.Of<T>()` is the concise way to satisfy a return type you never inspect.

The test then asserts on the entities themselves, which is what you actually want to know:

```csharp
Assert.Equal(2, capturedEntities.Count);
Assert.Equal("1001", capturedEntities[0].RowKey);
Assert.Equal("1002", capturedEntities[1].RowKey);
```

Capturing beats `Verify(...)` here: `Verify` proves a call happened, capture proves the **content**
was right. Row keys and partition keys are content.

## Faking `AsyncPageable<T>`

`QueryAsync<T>` returns `AsyncPageable<T>`. Moq cannot produce one. Subclass:

```csharp
private class MockAsyncEnumerable<T> : AsyncPageable<T> where T : notnull
{
    private readonly IEnumerable<Page<T>> _pages;

    public MockAsyncEnumerable(IEnumerable<Page<T>> pages) => _pages = pages;

    public override async IAsyncEnumerable<Page<T>> AsPages(
        string? continuationToken = null, int? pageSizeHint = null)
    {
        await Task.CompletedTask;
        foreach (var page in _pages) yield return page;
    }
}

private class MockPage<T> : Page<T> where T : notnull
{
    private readonly IReadOnlyList<T> _values;

    public MockPage(IEnumerable<T> values) => _values = values.ToList();

    public override IReadOnlyList<T> Values => _values;
    public override string? ContinuationToken => null;
    public override Response GetRawResponse() => Mock.Of<Response>();
}
```

`await Task.CompletedTask` is not decorative -- it is what lets the method be `async` so `yield
return` compiles into an `IAsyncEnumerable`. Remove it and the file does not build.

Wire it in:

```csharp
private void SetupOperatorLookup(IEnumerable<OperatorLookupEntity> lookupEntities)
{
    var mockPage = new MockPage<OperatorLookupEntity>(lookupEntities);
    var mockAsyncEnumerable = new MockAsyncEnumerable<OperatorLookupEntity>(new[] { mockPage });

    _mockOperatorLookupTable
        .Setup(x => x.QueryAsync<OperatorLookupEntity>(
            It.IsAny<string>(),
            It.IsAny<int?>(),
            It.IsAny<IEnumerable<string>>(),
            It.IsAny<CancellationToken>()))
        .Returns(mockAsyncEnumerable);
}
```

**Match the four-argument overload exactly.** `QueryAsync<T>` has several overloads -- one taking a
`string` filter and one taking an `Expression<Func<T, bool>>`. A `Setup` on the wrong overload
compiles, never matches, and `QueryAsync` returns `null` at runtime. If you get a null
`AsyncPageable`, this is why.

Return multiple `MockPage`s to test that a consumer handles pagination rather than reading only the
first page.

## What these fakes cannot tell you

A mocked `TableClient` accepts anything. It will not reject:

- a partition key mismatch inside a single `SubmitTransactionAsync` (the real service returns 400)
- a batch larger than 100 entities (the real service rejects it)
- a property type Table Storage cannot store
- a `RowKey` containing `/`, `\`, `#` or `?`

So these tests prove your *mapping* and *filtering* logic, not that the write will succeed. The
batch-size and partition rules have to be enforced in the code and reviewed, not tested here. See
`autoplan-data-persistence/references/batch-writes.md`.

Nothing in the estate uses Azurite, so there is no test anywhere that performs a real storage
round-trip.

## Watch the numeric type

```csharp
Assert.Equal(50.00, capturedEntities[0].AmountIncludingVat);
```

That literal is a `double`, and it compiles because `ParkingRowEntity.AmountIncludingVat` is a
`double`. If you change the entity property to `decimal`, this assertion stops compiling -- which is
the useful outcome, because `decimal` on an `ITableEntity` writes without an `@odata.type`
annotation and stores as whatever type the value implies. Do not "fix" it by casting the literal.
