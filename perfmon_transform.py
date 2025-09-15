import sys
import os
import pandas as pd

if len(sys.argv) < 2:
    print("Usage: perfmon_transform.py <input_csv>")
    sys.exit(1)

input_csv = sys.argv[1]

# Perfmon CSV sometimes has a PDH preamble line.
# Try normal read; if the first column header looks like PDH, re-read skipping 1.
df = pd.read_csv(input_csv, engine="python")
first_col = df.columns[0]
if isinstance(first_col, str) and "PDH-CSV" in first_col:
    df = pd.read_csv(input_csv, engine="python", skiprows=1)

# Coerce all data-like columns to numeric when possible (ignore timestamps/labels).
# We keep the first column (usually the timestamp) as index before transpose.
df = df.copy()
index_col = df.columns[0]
df.set_index(index_col, inplace=True)

# Transpose so each row is a counter/instance and columns are timestamps
df_t = df.transpose()

# Attempt numeric conversion where possible (non-numeric remain NaN)
for c in df_t.columns:
    df_t[c] = pd.to_numeric(df_t[c], errors="coerce")

# Compute row-wise Average across samples, sort descending
df_t["Average"] = df_t.mean(axis=1, skipna=True)
df_t.sort_values(by="Average", ascending=False, inplace=True)

# Save next to input or CWD (caller set CWD to the output folder)
out_path = os.path.join(os.getcwd(), "perfmon_transformed.csv")
df_t.to_csv(out_path, index=True)
print(f"Wrote: {out_path}")
