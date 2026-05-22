// tools/format_string_batch.csx
// F003: Set explicit Format String on ~40 measures
//
// Date:   2026-05-22
// Author: Ryszard Twardy
//
// Run in: Tabular Editor 2 -> Advanced Scripting tab -> paste -> F5 (Run)
//
// References:
//   - .checkpoints/AUDIT_FINDINGS_kupferkanne_2026-05-15.md § F003 (HIGH)
//   - D044 (Format String batch for ~40 measures)
//   - R041 (BPA + docs/measures.md sync same session)
//   - Issue: ryszard-twardy/rfm-customer-segmentation-kupferkanne#1
//
// Strategy:
//   1. Primary categorization by measure.DataType (String / DateTime / Int64)
//   2. Name-pattern disambiguation for Decimal/Double measures
//      (percent vs avg-score vs count-like vs currency)
//   3. Currency is the default for any unmatched Decimal/Double
//
// Safety:
//   - dryRun=true (default) -> preview only, no model changes
//   - Idempotent: skip if FormatString already matches proposed value
//   - Skips text-returning measures (DataType.String + name-pattern)
//   - Skips measures with non-numeric/non-date DataType
//   - Explicit manual-override list for measures with custom semantics
//   - Explicit currency-override list for false-positives from IsCountLike
//
// Reusable for F006 (Summarize By = None) — see Step 2 of post-F003 work.

bool dryRun = true;  // FLIP TO false AFTER REVIEWING DRY-RUN OUTPUT

// Canonical format strings (per D044 + F003 spec)
const string FMT_CURRENCY = "\"€\"#,##0.00;-\"€\"#,##0.00";  // €
const string FMT_PERCENT  = "0.00%";
const string FMT_COUNT    = "#,##0";
const string FMT_DECIMAL2 = "0.00";       // 2-decimal precision (e.g., avg scores)
const string FMT_DATE     = "dd-mmm-yyyy";

// --- Name-pattern helpers (applied to measure.Name) ---

// Percent: any name containing %, "Rate", or "Share"
// Examples: "Profit Margin %", "Line Margin %", "Segment % of Total",
//           "Country Revenue Share", "Reactivation Rate", "Retention Rate"
System.Func<string, bool> IsPercent = (n) =>
    n.Contains("%") ||
    n.Contains("Rate") ||
    n.Contains("Share");

// Text-returning measure indicators
// Examples: "Top Brand Name", "Top Category Name", "Health Indicator",
//           "R/F/M Labels", "Subtitle Page *", "Revenue Trend Chart Title",
//           "Dynamic KPI Label", "Segment Color"
System.Func<string, bool> IsTextName = (n) =>
    n.Contains("Name") ||
    n.Contains("Label") ||
    n.Contains("Indicator") ||
    n.Contains("Title") ||
    n.Contains("Subtitle") ||
    n.Contains("Color");

// Average score measures: Double-returning, 2-decimal precision
// Examples: "Avg R Score", "Avg F Score", "Avg M Score", "Avg Health Score"
// Must run BEFORE IsCountLike (which still catches "Score" as fallback for
// hypothetical Int64-returning total/median score measures).
System.Func<string, bool> IsAverageScore = (n) =>
    (n.StartsWith("Avg ") || n.StartsWith("Average ")) && n.Contains("Score");

// Count-like measures that may return Double (e.g., Avg Recency Days)
// Catches non-Int64 measures that should still render as whole numbers
System.Func<string, bool> IsCountLike = (n) =>
    n.Contains("Count") ||
    n.Contains("Customers") ||
    n.Contains("Orders") ||
    n.Contains("Products") ||
    n.Contains("Brands") ||
    n.Contains("Days") ||
    n.Contains("Frequency") ||
    n.Contains("Score") ||
    n.Contains("Distinct");

// Explicit currency overrides — measures that pattern-matching would miscategorize
// Examples: "ARPU by Country" — currency (Spend / users), but "Count" substring in "Country" trips IsCountLike
System.Func<string, bool> IsCurrencyExplicit = (n) =>
    n.StartsWith("ARPU") ||
    n.StartsWith("MRPU");  // future-proof: Marginal Revenue Per User if added later

// --- Explicit overrides ---
// Measures with custom semantics that pattern-matching mis-categorizes.
// Manual format preservation (do NOT touch FormatString):
//   - "Avg Health Score" — custom "0.0 ""/ 15""" display with /15 max suffix
//   - "Dynamic KPI Selector" — multi-KPI SWITCH measure, format depends on selected KPI (cannot be statically set)
//   - "Reactivation Rate Value" — Integer percentage POINTS (10/20/30), not ratio; "Rate" name pattern miscategorizes as percent
System.Func<string, bool> IsManualOverride = (n) =>
    n == "Avg Health Score" ||
    n == "Dynamic KPI Selector" ||
    n == "Reactivation Rate Value";

// --- Main loop ---

var changes = new List<KeyValuePair<string, string>>();  // (reason, formatted line)
var skipped = new List<string>();

foreach (var m in Model.AllMeasures) {
    string current  = m.FormatString ?? "";
    string proposed = null;
    string reason   = "";

    // Priority order:
    //   1. Manual override       — explicit name list -> skip
    //   2. Text (skip)           — by DataType.String OR name pattern
    //   3. Date                  — DataType.DateTime -> dd-mmm-yyyy
    //   4. Percent               — name has %/Rate/Share -> 0.00%
    //   5. Currency explicit     — ARPU/MRPU prefix -> "€"#,##0.00
    //   6. Avg Score             — "Avg * Score" Double-returning -> 0.00
    //   7. Count                 — DataType.Int64 OR count-like name -> #,##0
    //   8. Currency (default)    — any remaining Decimal/Double -> "€"#,##0.00
    //   9. Unknown (skip)        — any other DataType

    if (IsManualOverride(m.Name)) {
        skipped.Add(string.Format("{0} [manual override -> skip]", m.Name));
        continue;
    }

    if (m.DataType == DataType.String || IsTextName(m.Name)) {
        skipped.Add(string.Format("{0} [text -> skip]", m.Name));
        continue;
    }

    if (m.DataType == DataType.DateTime) {
        proposed = FMT_DATE;
        reason   = "date";
    }
    else if (IsPercent(m.Name)) {
        proposed = FMT_PERCENT;
        reason   = "percent (by name)";
    }
    else if (IsCurrencyExplicit(m.Name)) {
        proposed = FMT_CURRENCY;
        reason   = "currency (explicit override)";
    }
    else if (IsAverageScore(m.Name)) {
        proposed = FMT_DECIMAL2;
        reason   = "decimal-2 (avg score)";
    }
    else if (m.DataType == DataType.Int64 || IsCountLike(m.Name)) {
        proposed = FMT_COUNT;
        reason   = "count";
    }
    else if (m.DataType == DataType.Decimal || m.DataType == DataType.Double) {
        proposed = FMT_CURRENCY;
        reason   = "currency (Decimal/Double default)";
    }
    else {
        skipped.Add(string.Format("{0} [unknown DataType={1} -> skip]", m.Name, m.DataType));
        continue;
    }

    if (current == proposed) {
        skipped.Add(string.Format("{0} [already correct: '{1}']", m.Name, current));
        continue;
    }

    changes.Add(new KeyValuePair<string, string>(
        reason,
        string.Format("{0,-42} | '{1}' -> '{2}'", m.Name, current, proposed)
    ));

    if (!dryRun) {
        m.FormatString = proposed;
    }
}

// --- Output summary (grouped by reason) ---

string mode = dryRun ? "DRY RUN (no changes applied — flip dryRun=false to apply)" : "APPLIED";

var sb = new System.Text.StringBuilder();
sb.AppendLine("=== F003 Format String Batch — " + mode + " ===");
sb.AppendLine(string.Format("Changed: {0}", changes.Count));
sb.AppendLine(string.Format("Skipped: {0}", skipped.Count));
sb.AppendLine();
sb.AppendLine("--- CHANGES (grouped by reason) ---");
foreach (var grp in changes.GroupBy(kv => kv.Key).OrderBy(g => g.Key)) {
    sb.AppendLine();
    sb.AppendLine(string.Format("[{0}] ({1} measures)", grp.Key, grp.Count()));
    foreach (var kv in grp) {
        sb.AppendLine("  " + kv.Value);
    }
}
sb.AppendLine();
sb.AppendLine("--- SKIPPED ---");
foreach (var s in skipped) sb.AppendLine(s);

Output(sb.ToString());
