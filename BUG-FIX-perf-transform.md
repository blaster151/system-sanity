# Bug Fix: perf_transform_cli.py - November 1, 2025

## Issue
```
UnboundLocalError: cannot access local variable 'enhanced_stats_rows' where it is not associated with a value
```

## Root Cause
The script had a logic error where it was trying to:
1. Sort `enhanced_stats_rows` 
2. Write `enhanced_stats_rows` to CSV
3. **THEN** build `enhanced_stats_rows`

This caused an `UnboundLocalError` because the variable was referenced before it was defined.

## Fix
Reordered the code to follow proper sequence:

### Before (Broken):
```python
# Line 117-122 (WRONG ORDER)
transposed.sort(...)
write_csv(..., transposed)

# ERROR: Using enhanced_stats_rows before it exists!
enhanced_stats_rows.sort(...)  
write_csv(..., enhanced_stats_rows)

# Line 139-167 (MUCH LATER)
enhanced_stats_rows = []  # NOW we define it
# ... build the rows ...
```

### After (Fixed):
```python
# Line 117-119
transposed.sort(...)
write_csv(..., transposed)

# Line 139-167 - BUILD enhanced_stats_rows first
enhanced_stats_rows = []
# ... build the rows ...
enhanced_stats_rows.append([...])

# Line 168-172 - THEN sort and write
enhanced_stats_rows.sort(key=lambda r: to_float(r[4]) or 0.0, reverse=True)
write_csv(os.path.join(outdir,"perf_stats.csv"),
          ["PID","Counter","Min","Max","Average"], enhanced_stats_rows)
```

## What Was Removed
Removed premature reference to `enhanced_stats_rows` at line ~120:
```python
# REMOVED: This was causing the error
enhanced_stats_rows.sort(key=lambda r: to_float(r[4]) or 0.0, reverse=True)
write_csv(os.path.join(outdir,"perf_stats.csv"),
          ["PID","Counter","Min","Max","Average"], enhanced_stats_rows)
```

## What Was Added
Added proper sort and write after building the data at line ~168:
```python
# ADDED: Proper location after enhanced_stats_rows is built
enhanced_stats_rows.sort(key=lambda r: to_float(r[4]) or 0.0, reverse=True)
write_csv(os.path.join(outdir,"perf_stats.csv"),
          ["PID","Counter","Min","Max","Average"], enhanced_stats_rows)
```

## Result
The script now:
1. ✅ Builds `enhanced_stats_rows` list
2. ✅ Sorts the list by average value (column 4)
3. ✅ Writes the sorted list to `perf_stats.csv`
4. ✅ No more UnboundLocalError

## Files Generated
When `-Capture` is used, the following files are properly generated:
- `out/perf_transposed.csv` - Transposed performance data with averages
- `out/perf_stats.csv` - Min/Max/Average statistics for each counter
- `out/latest_snapshot.csv` - Latest snapshot of all counters
- `out/top_cpu_labeled.csv` - Top CPU consumers labeled with service names
- `out/report.html` - HTML report generated from the above data

## Testing
To test:
```powershell
.\run-sanity.bat -Capture -DurationSecs 30
```

Should complete without errors and open `out/report.html` in browser.
