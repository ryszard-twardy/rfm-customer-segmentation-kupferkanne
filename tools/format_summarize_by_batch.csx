// tools/format_summarize_by_batch.csx
// Batch-set SummarizeBy = None on 32 non-additive numeric columns (Tabular Editor 2).
//
// Date:   2026-05-24
// Author: Ryszard Twardy
//
// Run in: Tabular Editor 2 -> Advanced Scripting tab -> paste -> F5 (Run)
//
// References:
//   - docs/measures.md – "Column Behavior: SummarizeBy = None" section
//   - BPA rule: "Do not summarize numeric columns" (enforced by this script)
//
// Strategy:
//   - Explicit (table, column) targets list – no pattern matching
//   - 32 governance targets
//
// Safety:
//   - dryRun=true default
//   - Idempotent: skip if SummarizeBy already None
//   - Per-target try/catch – log missing cols, continue (defensive against
//     column rename / table reorg drift)
//   - Uses KeyValuePair<string,string> for targets (TE2's embedded Roslyn
//     predates C# 7.0; value tuples fail to compile)
//
// Reusable for any future "set SummarizeBy=None on N cols" batch.

bool dryRun = true;

var targets = new List<KeyValuePair<string, string>> {
    new KeyValuePair<string, string>("dim_Customer", "Recency Days"),
    new KeyValuePair<string, string>("dim_Customer", "Order Count"),
    new KeyValuePair<string, string>("dim_Customer", "Total Spend"),
    new KeyValuePair<string, string>("dim_Customer", "Total Profit"),
    new KeyValuePair<string, string>("dim_Customer", "Margin %"),
    new KeyValuePair<string, string>("dim_Customer", "Total Units"),
    new KeyValuePair<string, string>("dim_Customer", "Avg Products per Order"),
    new KeyValuePair<string, string>("dim_Customer", "R Score"),
    new KeyValuePair<string, string>("dim_Customer", "F Score"),
    new KeyValuePair<string, string>("dim_Customer", "M Score"),
    new KeyValuePair<string, string>("dim_Customer", "Health Score"),
    new KeyValuePair<string, string>("dim_Date", "Year"),
    new KeyValuePair<string, string>("dim_Date", "Month"),
    new KeyValuePair<string, string>("dim_Date", "Week of Year"),
    new KeyValuePair<string, string>("dim_Date", "Day"),
    new KeyValuePair<string, string>("dim_Date", "Day Number"),
    new KeyValuePair<string, string>("dim_Date", "Year-Month-Number"),
    new KeyValuePair<string, string>("dim_Segment", "SortOrder"),
    new KeyValuePair<string, string>("sales_curated", "Order Discount %"),
    new KeyValuePair<string, string>("sales_curated", "Basket Item Count"),
    new KeyValuePair<string, string>("sales_curated", "Order Value"),
    new KeyValuePair<string, string>("sales_curated", "Order Cost"),
    new KeyValuePair<string, string>("sales_curated", "Order Profit"),
    new KeyValuePair<string, string>("sales_curated", "Order Margin %"),
    new KeyValuePair<string, string>("sales_curated", "Total Units"),
    new KeyValuePair<string, string>("sales_curated", "Distinct Products"),
    new KeyValuePair<string, string>("sales_curated", "Source Month"),
    new KeyValuePair<string, string>("v_items_for_bi", "Quantity"),
    new KeyValuePair<string, string>("v_items_for_bi", "Line Net Amount"),
    new KeyValuePair<string, string>("v_items_for_bi", "Line Profit"),
    new KeyValuePair<string, string>("v_items_for_bi", "Line Margin %"),
    new KeyValuePair<string, string>("dim_KPI_Selector", "SortOrder")
};

var changes = new List<KeyValuePair<string, string>>();
var skipped = new List<string>();
var missing = new List<string>();

foreach (var target in targets) {
    string tableName = target.Key;
    string columnName = target.Value;
    var table = Model.Tables.FirstOrDefault(t => t.Name == tableName);
    if (table == null) {
        missing.Add(string.Format("{0}.{1} [table not found]", tableName, columnName));
        continue;
    }

    var column = table.Columns.FirstOrDefault(c => c.Name == columnName);
    if (column == null) {
        missing.Add(string.Format("{0}.{1} [column not found in table]", tableName, columnName));
        continue;
    }

    var currentSummarize = column.SummarizeBy;
    if (currentSummarize == AggregateFunction.None) {
        skipped.Add(string.Format("{0}.{1} [already SummarizeBy=None]", tableName, columnName));
        continue;
    }

    var reason = "set SummarizeBy=None (was " + currentSummarize.ToString() + ")";
    changes.Add(new KeyValuePair<string, string>(reason,
        string.Format("{0,-25}.{1,-30} | {2} -> None", tableName, columnName, currentSummarize)));

    if (!dryRun) {
        column.SummarizeBy = AggregateFunction.None;
    }
}

// Output summary (grouped by reason)
string mode = dryRun ? "DRY RUN (no changes applied – flip dryRun=false to apply)" : "APPLIED";

var sb = new System.Text.StringBuilder();
sb.AppendLine("=== SummarizeBy Batch – " + mode + " ===");
sb.AppendLine(string.Format("Targets: {0}", targets.Count));
sb.AppendLine(string.Format("Changed: {0}", changes.Count));
sb.AppendLine(string.Format("Skipped: {0}", skipped.Count));
sb.AppendLine(string.Format("Missing: {0}", missing.Count));
sb.AppendLine();

sb.AppendLine("--- CHANGES (grouped by reason) ---");
var grouped = changes.GroupBy(c => c.Key).OrderBy(g => g.Key);
foreach (var group in grouped) {
    sb.AppendLine(string.Format("[{0}] ({1} cols)", group.Key, group.Count()));
    foreach (var entry in group) sb.AppendLine("  " + entry.Value);
    sb.AppendLine();
}

sb.AppendLine("--- SKIPPED (idempotent) ---");
foreach (var s in skipped) sb.AppendLine(s);
sb.AppendLine();

if (missing.Count > 0) {
    sb.AppendLine("--- MISSING (audit drift) ---");
    foreach (var m in missing) sb.AppendLine(m);
}

Output(sb.ToString());
