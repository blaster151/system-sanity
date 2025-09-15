#!/usr/bin/env python3
# Transpose + Average + Sort with robust header detection (no external deps)
import csv, sys, os, re

def to_float(x):
    try:
        return float(x)
    except Exception:
        return None

def sniff_header(rows):
    """
    rows: list of non-empty CSV rows.
    Returns (header_row_index) where that row should be used as header.
    Heuristics:
      - skip PDH preamble (row containing 'PDH-CSV')
      - prefer a row whose first cell equals 'Time' (typeperf default)
      - otherwise pick the first row that contains any counter-looking token '\Process('
      - fallback to row 0
    """
    for i, r in enumerate(rows[:5]):
        if any("PDH-CSV" in c for c in r):
            continue
        if len(r) and r[0].strip().lower() == "time":
            return i
    for i, r in enumerate(rows[:5]):
        line = ",".join(r)
        if "\\Process(" in line or line.startswith("\\"):
            return i
    return 0

def read_csv_lines(path):
    with open(path, "r", newline="", encoding="utf-8", errors="ignore") as f:
        rdr = csv.reader(f)
        rows = [row for row in rdr if row]
    return rows

def main():
    if len(sys.argv) < 2:
        print("Usage: perfmon_transform_nopandas.py <input_csv> [output_csv]")
        sys.exit(1)

    in_path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) >= 3 else os.path.splitext(in_path)[0] + "_transformed.csv"

    rows = read_csv_lines(in_path)
    if not rows:
        print("No rows found.")
        sys.exit(2)

    # Drop PDH line(s) up front for sniffing
    core = [r for r in rows if not any("PDH-CSV" in c for c in r)]
    if not core:
        core = rows

    hdr_idx = sniff_header(core)
    header = core[hdr_idx]
    data = core[hdr_idx + 1:]

    # Defensive: normalize widths
    width = len(header)
    norm = [r + [""] * (width - len(r)) for r in data]

    # First column = timestamps
    timestamps = [r[0] for r in norm]

    # Transpose: output rows = original columns (counters)
    out_rows = []
    for col in range(1, width):   # skip the time column 0
        label = header[col].strip()
        series = [norm[r][col] for r in range(len(norm))]
        nums = [to_float(v) for v in series]
        nums_clean = [v for v in nums if v is not None]
        avg = (sum(nums_clean) / len(nums_clean)) if nums_clean else 0.0
        out_rows.append([label] + series + [f"{avg:.6f}"])

    # Sort by Average desc
    def key_last_float(row):
        v = to_float(row[-1])
        return v if v is not None else 0.0
    out_rows.sort(key=key_last_float, reverse=True)

    out_header = ["Counter"] + timestamps + ["Average"]
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(out_header)
        w.writerows(out_rows)

    print(f"Wrote: {out_path}")

if __name__ == "__main__":
    main()