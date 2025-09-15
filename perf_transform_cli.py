#!/usr/bin/env python3
# Robust typeperf transformer (no external deps), now with Min/Max/Avg stats.
# Inputs : out/typeperf_SD.csv, out/service-process-map.csv
# Outputs: out/perf_transposed.csv, out/latest_snapshot.csv, out/top_cpu_labeled.csv, out/perf_stats.csv

import csv, sys, os, re
from statistics import mean

def to_float(x):
    try: return float(x)
    except: return None

def read_rows(path):
    with open(path, "r", newline="", encoding="utf-8", errors="ignore") as f:
        r = csv.reader(f)
        return [row for row in r if row]

def drop_pdh(rows):
    return [r for r in rows if not any("PDH-CSV" in c for c in r)]

def looks_like_counters(header_row):
    if not header_row or len(header_row) < 2: return False
    h0 = header_row[0].strip().lower()
    h1 = header_row[1].strip()
    # Typeperf "Time" then counters like "\Processor(_Total)\% Processor Time"
    if h0 == "time" and (h1.startswith("\\") or "\\Process(" in h1): return True
    # Also check for PDH-CSV format where first column is PDH-CSV and second is a counter
    if "pdh-csv" in h0 and (h1.startswith("\\") or "\\Process(" in h1): return True
    return False

def find_header(core):
    # Prefer the first row that looks like a counter header; fallback to row 0.
    for i in range(min(5, len(core))):
        if looks_like_counters(core[i]): return i
    return 0

def normalize_width(rows, width):
    return [row + [""]*(width - len(row)) for row in rows]

def parse_process_label(lbl):
    m = re.match(r'^\\Process\((.*?)\)\\(.*)$', lbl.strip())
    return (m.group(1), m.group(2)) if m else (None, lbl.strip())

def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(header); w.writerows(rows)

def main():
    here   = os.path.abspath(os.path.dirname(__file__))
    outdir = os.path.join(here, "out")
    perf   = os.path.join(outdir, "typeperf_SD.csv")
    svcmap = os.path.join(outdir, "service-process-map.csv")
    if not os.path.exists(perf):
        print(f"ERROR: missing perf CSV: {perf}"); sys.exit(1)

    rows = read_rows(perf)
    
    # For typeperf, the first row contains the counter names, second row contains timestamps
    # We need to use the first row as header (counter names) and second row as timestamp header
    if len(rows) >= 2:
        # First row: counter names (including PDH-CSV in first column)
        counter_header = rows[0]
        # Second row: timestamps (first column is timestamp, rest are data)
        timestamp_row = rows[1]
        # Data starts from third row
        data = rows[2:]
        
        # Use counter names as header, but skip the first column (PDH-CSV)
        header = counter_header[1:]  # Skip PDH-CSV column
        # Add timestamp column name
        header = ["Time"] + header
    else:
        # Fallback to old logic
        core = drop_pdh(rows) or rows
        hdr_idx = find_header(core)
        header  = core[hdr_idx]
        data    = core[hdr_idx+1:]

    if len(header) < 2 or not data:
        print("ERROR: unexpected CSV shape (no header or no data)"); sys.exit(2)

    width = len(header)
    data  = normalize_width(data, width)
    
    # Extract timestamps from the data rows (first column of each data row)
    times = [r[0] for r in data]

    # --- Transpose with labels preserved
    transposed = []
    stats_rows = []
    for c in range(1, width):
        label  = header[c].strip()
        series = [data[r][c] for r in range(len(data))]
        nums   = [to_float(v) for v in series]
        nums   = [v for v in nums if v is not None]
        avg = mean(nums) if nums else 0.0
        mn  = min(nums)  if nums else 0.0
        mx  = max(nums)  if nums else 0.0
        transposed.append([label] + series + [f"{avg:.6f}"])
        stats_rows.append([label, f"{mn:.6f}", f"{mx:.6f}", f"{avg:.6f}"])

    transposed.sort(key=lambda r: to_float(r[-1]) or 0.0, reverse=True)
    write_csv(os.path.join(outdir,"perf_transposed.csv"),
              ["Counter"] + times + ["Average"], transposed)
    write_csv(os.path.join(outdir,"perf_stats.csv"),
              ["Counter","Min","Max","Average"], sorted(stats_rows, key=lambda r: to_float(r[-1]) or 0.0, reverse=True))

    # --- Latest snapshot (flatten) + PID correlation
    latest_i  = len(times)-1
    latest_ts = times[-1]
    latest_rows = []
    pid_by_instance = {}
    for c in range(1, width):
        label = header[c].strip()
        val   = data[latest_i][c] if latest_i >= 0 else ""
        inst, metric = parse_process_label(label)
        if inst is not None:
            latest_rows.append([latest_ts, "Process", inst, metric, val])
            if metric == "ID Process":
                v = to_float(val)
                if v is not None: pid_by_instance[inst] = int(v)
        else:
            latest_rows.append([latest_ts, "Counter", "", label, val])

    write_csv(os.path.join(outdir,"latest_snapshot.csv"),
              ["Time","Kind","Instance","Metric","Value"], latest_rows)

    # --- Top CPU labeled with services
    cpu_rows = []
    for t, kind, inst, metric, val in latest_rows:
        if kind=="Process" and metric=="% Processor Time":
            cpu = to_float(val) or 0.0
            pid = pid_by_instance.get(inst)
            cpu_rows.append([inst, cpu, pid])

    svc_by_pid = {}
    if os.path.exists(svcmap):
        with open(svcmap,"r",newline="",encoding="utf-8",errors="ignore") as f:
            rdr = csv.DictReader(f)
            for r in rdr:
                try: pid = int(r.get("ProcessId") or r.get("PID") or "")
                except: continue
                name = (r.get("Name") or "").strip()
                disp = (r.get("DisplayName") or "").strip()
                svc_by_pid.setdefault(pid, {"names":set(),"disps":set()})
                if name: svc_by_pid[pid]["names"].add(name)
                if disp: svc_by_pid[pid]["disps"].add(disp)

    rows_out = []
    for inst, cpu, pid in cpu_rows:
        names = disps = ""
        if pid and pid in svc_by_pid:
            names = ", ".join(sorted(svc_by_pid[pid]["names"]))
            disps = ", ".join(sorted(svc_by_pid[pid]["disps"]))
        rows_out.append([inst, pid if pid is not None else "", f"{cpu:.3f}", names, disps])
    rows_out.sort(key=lambda r: float(r[2]), reverse=True)

    write_csv(os.path.join(outdir,"top_cpu_labeled.csv"),
              ["Instance","PID","CPU_ProcTime","SvcNames","SvcDisplayNames"], rows_out)

    print("Wrote: out/perf_transposed.csv, out/perf_stats.csv, out/latest_snapshot.csv, out/top_cpu_labeled.csv")

if __name__ == "__main__":
    main()