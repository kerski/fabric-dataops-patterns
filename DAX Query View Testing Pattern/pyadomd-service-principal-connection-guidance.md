# Using pyadomd with Service Principal, EffectiveUserName, and Roles

This note maps the `Invoke-DQVTesting.psm1` connection-string behavior to Python (`pyadomd`, sometimes written as "pythonamod"/"pythoamod").

## What the PowerShell module is doing

In `modules/Invoke-DQVTesting/Invoke-DQVTesting.psm1`, `New-TestingObj` builds these patterns:

- **Service principal**
  - `User ID="app:<client-id>@<tenant-id>"`
  - `Password=<client-secret>`
  - `Integrated Security=ClaimsToken`
- **User credential**
  - `User ID=<username>`
  - `Password=<password>`
  - `Integrated Security=ClaimsToken`

It also uses:

- `Provider=MSOLAP`
- `Data Source=powerbi://api.powerbi.com/v1.0/myorg/<workspace>`
- `Database=<semantic model name>`

## Python approach (pyadomd)

Use the same base connection string and append impersonation/security context when needed.

```python
from pyadomd import Pyadomd

def build_conn_str(
    workspace_name: str,
    dataset_name: str,
    client_id: str,
    client_secret: str,
    tenant_id: str,
    effective_username: str | None = None,
    roles: list[str] | None = None,
) -> str:
    parts = [
        "Provider=MSOLAP",
        f"Data Source=powerbi://api.powerbi.com/v1.0/myorg/{workspace_name}",
        f"Database={dataset_name}",
        f"User ID=app:{client_id}@{tenant_id}",
        f"Password={client_secret}",
        "Integrated Security=ClaimsToken",
    ]

    # Optional impersonation for RLS validation
    if effective_username:
        parts.append(f"EffectiveUserName={effective_username}")

    # Optional role filter (comma separated)
    if roles:
        parts.append(f"Roles={','.join(roles)}")

    return ";".join(parts) + ";"


conn_str = build_conn_str(
    workspace_name="<workspace>",
    dataset_name="<semantic-model>",
    client_id="<app-id-guid>",
    client_secret="<app-secret>",
    tenant_id="<tenant-id-guid>",
    effective_username="user@contoso.com",  # optional
    roles=["Sales", "NorthAmerica"],      # optional
)

with Pyadomd(conn_str) as conn:
    with conn.cursor().execute("EVALUATE ROW(\"Ping\", 1)") as cur:
        rows = cur.fetchall()
        print(rows)
```

## Recommended validation checklist

1. **No impersonation**: run a basic query with only service principal values.
2. **Effective user only**: set `EffectiveUserName` and validate RLS behavior changes for that user.
3. **Effective user + roles**: add `Roles=...` and confirm role-scoped output.
4. **Negative test**: set a non-existent role and confirm expected failure.
5. **Do not log secrets**: never print the full connection string in pipeline logs.

## Notes for your other project

- Keep the service principal format exactly aligned with this repo’s PowerShell module:
  - `User ID=app:<client-id>@<tenant-id>`
  - `Integrated Security=ClaimsToken`
- Add `EffectiveUserName` and `Roles` only when you are explicitly testing impersonation/RLS.
- Ensure the service principal has XMLA read permissions and dataset access in the workspace.
