# The four-layer model chain

## Layers

| Layer | File (HubSpot) | Purpose | Width |
|---|---|---|---|
| API types | `src/HubSpot.Connector/Models/Types.cs` (1085 lines) | Faithful shape of the API response. Nothing is dropped or renamed here. | widest |
| Table entity | `Models/TableEntities.cs` (373 lines) | Hot subset stored in Azure Table Storage for cheap lookup. | narrowest |
| DB model | `Models/DbModels.cs` (464 lines) | The full record as persisted to SQL Server. | wide |
| SQL columns | `sql/01_Initialize_Tables.sql` + `InitializeDatabaseAsync` | Physical schema. | wide |

Mapping between layers is explicit and hand-written in `Services/MappingService.cs` (691 lines):
`MappingService.ToTableEntity(...)` and `MappingService.ToDbModel(...)`.

There is no AutoMapper and no convention-based binding. That is deliberate -- the mapping is the
place where API quirks get normalised -- but it means **nothing tells you when a layer falls behind**.

## What may legitimately drop between layers

- **API type -> table entity.** Most properties. The table entity holds only what is queried
  frequently. HubSpot maps roughly 150 of 300+ properties here. Dropping is expected.
- **API type -> DB model.** Little should drop; this is the archive of record.
- **DB model -> SQL columns.** Nothing may drop. A property without a column is data loss.

Per HubSpot's own `MAPPINGSERVICE_UPDATE.md`, the intended widths are:

| Object | TableEntity | DbModel |
|---|---|---|
| Companies | 50+ | 60+ |
| Contacts | 35+ | 50+ |
| Deals | 40+ | 90+ |
| Tickets | 25+ | 40+ |

Treat these as the design intent, not a measurement -- the document reports them as "50+" style
approximations and was written from the code, not generated from it.

## Adding a field end to end

Four edits. Do all four in the same change, in this order:

1. **DB model** -- add the property to `DbModels.cs` with the right nullability. If the API can omit
   it, the property is nullable. Most API fields can be omitted.
2. **Schema script** -- add the column to both the `CREATE TABLE` in the initialize script *and* an
   additive `ALTER TABLE ... ADD` in the update script. See [schema-scripts.md](schema-scripts.md).
3. **MERGE statement** -- add `Column = @Column` to the `WHEN MATCHED THEN UPDATE SET` list, and add
   the column to **both** the `INSERT (...)` column list and its `VALUES (...)` list. These three
   edits are separate and it is common to make only two of them.
4. **Mapping** -- populate the property in `MappingService.ToDbModel`. Without this the column is
   written as `NULL` forever, which looks like an upstream data problem rather than a mapping bug.

Then run both check scripts from the SKILL, and execute one real save.

## Failure signatures

| Symptom | Which edit was missed |
|---|---|
| `Must declare the scalar variable "@X"` | MERGE references `@X`; no property `X` on the model. |
| `Invalid column name 'X'` | MERGE writes column `X`; no column in the table. Schema script not run, or not updated. |
| Column exists and is always `NULL` | Mapping never populates it (edit 4). |
| Property populated in C#, column never changes | Property missing from the MERGE update list (edit 3). |
| Insert works, update does not (or vice versa) | Only one of the two MERGE branches was edited. |

The last two are the dangerous ones: no error, no log entry, and the data simply is not there.

## Why the mapping direction matters

`MappingService` is static and one-way (API type -> storage shape). There is no reverse mapping and
no round-trip test in this estate. If you add a reverse path, add a round-trip test with it -- see
the `autoplan-integration-testing` skill for what is worth covering.
