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
    # Handle both formats: "\Process(...)\Metric" and "\\MACHINE\Process(...)\Metric"
    m = re.match(r'^\\\\.*?\\Process\((.*?)\)\\(.*)$', lbl.strip())
    if not m:
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
    # Optional browser mapping artifacts created by chrome_debugger_extract.ps1
    browser_proc_csv = os.path.join(outdir, "browser-tabs-processes.csv")
    browser_tabs_csv = os.path.join(outdir, "browser-tabs.csv")
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

    # Only include meaningful performance metrics in stats (not Process IDs or other metadata)
    meaningful_metrics = [
        "% Processor Time", "Working Set", "Private Bytes", "Virtual Bytes",
        "Handle Count", "Thread Count", "IO Read Operations/sec", "IO Write Operations/sec",
        "Available MBytes", "% Committed Bytes In Use", "Cache Bytes"
    ]

    for c in range(1, width):
        label  = header[c].strip()
        series = [data[r][c] for r in range(len(data))]
        nums   = [to_float(v) for v in series]
        nums   = [v for v in nums if v is not None]
        avg = mean(nums) if nums else 0.0
        mn  = min(nums)  if nums else 0.0
        mx  = max(nums)  if nums else 0.0
        transposed.append([label] + series + [f"{avg:.6f}"])

        # Only include in stats if it's a meaningful performance metric
        inst, metric = parse_process_label(label)
        if (metric in meaningful_metrics or
            (inst is None and any(m in label for m in meaningful_metrics))):
            stats_rows.append([label, f"{mn:.6f}", f"{mx:.6f}", f"{avg:.6f}"])

    transposed.sort(key=lambda r: to_float(r[-1]) or 0.0, reverse=True)
    write_csv(os.path.join(outdir,"perf_transposed.csv"),
              ["Counter"] + times + ["Average"], transposed)

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
                if v is not None: 
                    pid_by_instance[inst] = int(v)
        else:
            latest_rows.append([latest_ts, "Counter", "", label, val])

    write_csv(os.path.join(outdir,"latest_snapshot.csv"),
              ["Time","Kind","Instance","Metric","Value"], latest_rows)

    # --- Load service-to-PID mapping first (used by both stats and top CPU)
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

    # --- Build optional browser PID->details map
    browser_by_pid = {}
    # Process details: PID, Type (e.g., Chrome: renderer), RAMMB, CommandLine
    if os.path.exists(browser_proc_csv):
        try:
            with open(browser_proc_csv, "r", newline="", encoding="utf-8", errors="ignore") as f:
                rdr = csv.DictReader(f)
                for r in rdr:
                    pid = r.get("PID")
                    if not pid: continue
                    try:
                        pid_i = int(pid)
                    except:
                        continue
                    typ = (r.get("Type") or "").strip()
                    browser_by_pid.setdefault(pid_i, {"types": set(), "hints": set()})
                    if typ:
                        browser_by_pid[pid_i]["types"].add(typ)
        except Exception as e:
            pass
    # Tab details: ProcessID, Type (Web Page/Extension/Service Worker), Title/Details/URL
    if os.path.exists(browser_tabs_csv):
        try:
            with open(browser_tabs_csv, "r", newline="", encoding="utf-8", errors="ignore") as f:
                rdr = csv.DictReader(f)
                for r in rdr:
                    pid = r.get("ProcessID")
                    if not pid: continue
                    try:
                        pid_i = int(pid)
                    except:
                        continue
                    typ = (r.get("Type") or "").strip()
                    title = (r.get("Title") or "").strip()
                    details = (r.get("Details") or "").strip()
                    domain = ""
                    # Derive domain from Details like "Domain: example.com"
                    if details.lower().startswith("domain:"):
                        domain = details.split(":",1)[1].strip()
                    hint_parts = []
                    if typ: hint_parts.append(typ)
                    if domain: hint_parts.append(domain)
                    elif title: hint_parts.append(title)
                    hint = ", ".join(hint_parts)
                    if hint:
                        browser_by_pid.setdefault(pid_i, {"types": set(), "hints": set()})
                        browser_by_pid[pid_i]["hints"].add(hint)
        except Exception as e:
            pass

    # --- Enhanced stats with PIDs and Service/Browser Names
    enhanced_stats_rows = []
    meaningful_metrics = [
        "% Processor Time", "Working Set", "Private Bytes", "Virtual Bytes",
        "Handle Count", "Thread Count", "IO Read Operations/sec", "IO Write Operations/sec"
    ]

    for c in range(1, width):
        label  = header[c].strip()
        series = [data[r][c] for r in range(len(data))]
        nums   = [to_float(v) for v in series]
        nums   = [v for v in nums if v is not None]
        avg = mean(nums) if nums else 0.0
        mn  = min(nums)  if nums else 0.0
        mx  = max(nums)  if nums else 0.0

        # Parse the counter to see if it's process-specific
        inst, metric = parse_process_label(label)

        # Only include in enhanced stats if it's a meaningful performance metric
        if (metric in meaningful_metrics or
            (inst is None and any(m in label for m in meaningful_metrics))):

            # For process-specific metrics, add PID if available
            pid = ""
            svc_names = ""
            if inst is not None:
                # Check if we have a PID for this instance
                if inst in pid_by_instance:
                    pid = str(pid_by_instance[inst])
                else:
                    # Try without instance number suffix (e.g., "chrome#1" -> "chrome")
                    base_inst = inst.split('#')[0]
                    if base_inst in pid_by_instance:
                        pid = str(pid_by_instance[base_inst])
                
                # Get service names or browser hints for this PID
                if pid:
                    pid_int = int(pid)
                    if pid_int in svc_by_pid:
                        svc_names = ", ".join(sorted(svc_by_pid[pid_int]["names"]))
                    elif pid_int in browser_by_pid:
                        # Prefer concise browser hint (Type + Domain/Title)
                        hints = browser_by_pid[pid_int].get("hints") or set()
                        types = browser_by_pid[pid_int].get("types") or set()
                        # Build a single short string
                        pieces = []
                        if types:
                            pieces.append("/".join(sorted(types))[:60])
                        if hints:
                            pieces.append("; ".join(sorted(hints))[:80])
                        svc_names = " | ".join([p for p in pieces if p])

            enhanced_stats_rows.append([pid, svc_names, label, f"{mn:.6f}", f"{mx:.6f}", f"{avg:.6f}"])

    # Sort enhanced stats by average value (descending)
    enhanced_stats_rows.sort(key=lambda r: to_float(r[5]) or 0.0, reverse=True)
    
    # Write enhanced stats
    write_csv(os.path.join(outdir,"perf_stats.csv"),
              ["PID","Service","Counter","Min","Max","Average"], enhanced_stats_rows)

    # --- Top CPU labeled with services
    cpu_rows = []
    for t, kind, inst, metric, val in latest_rows:
        if kind=="Process" and metric=="% Processor Time":
            cpu = to_float(val) or 0.0
            pid = pid_by_instance.get(inst)
            cpu_rows.append([inst, cpu, pid])

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