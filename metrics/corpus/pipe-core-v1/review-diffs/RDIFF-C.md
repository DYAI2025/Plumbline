# PR for review: add CSV export of orders

`src/export.py`:
```python
class OrderExporter:
    def __init__(self, db):
        self.db = db
    def export_orders_csv(self, requesting_user):
        rows = self.db.all_orders()           # fetch orders
        out = ["id,customer,amount,note"]
        for o in rows:
            out.append(f"{o.id},{o.customer},{o.amount},{o.note}")
        return "\n".join(out)
```
Wiring: `build_app()` constructs `OrderExporter(db)`; the `GET /orders/export` route calls
`exporter.export_orders_csv(current_user)` and returns the CSV body. Confirmed wired into
the running app.
Tests (all green): export returns a CSV string with a header row and one line per order.
