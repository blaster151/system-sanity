#!/usr/bin/env python3
import csv, os, html, datetime

here=os.path.abspath(os.path.dirname(__file__)); outdir=os.path.join(here,"out")
def read_csv(p): 
    p=os.path.join(outdir,p)
    if not os.path.exists(p): return []
    with open(p,"r",newline="",encoding="utf-8",errors="ignore") as f:
        return [r for r in csv.reader(f)]

top   = read_csv("top_cpu_labeled.csv")
snap  = read_csv("latest_snapshot.csv")
stats = read_csv("perf_stats.csv")           # <<< compact Min/Max/Avg table

# Optional browser process map (for type breakdown)
def read_browser_proc_map():
  p = os.path.join(outdir, "browser-tabs-processes.csv")
  if not os.path.exists(p):
    return {}
  out = {}
  try:
    with open(p, "r", newline="", encoding="utf-8", errors="ignore") as f:
      rdr = csv.DictReader(f)
      for r in rdr:
        pid = (r.get("PID") or "").strip()
        b = (r.get("Browser") or "").strip()
        typ = (r.get("Type") or "").strip()
        if pid and pid.isdigit():
          out[int(pid)] = {"browser": b, "type": typ}
  except Exception:
    return {}
  return out

def table_html(title, rows, freeze_first=False):
  if not rows:
    return f"<h2>{html.escape(title)}</h2><p><em>No data</em></p>"
  head, data = rows[0], rows[1:]
  thead = "".join(f"<th>{html.escape(h)}</th>" for h in head)
  body = []
  for r in data:
    tds = []
    for i, c in enumerate(r):
      cls = ' class="firstcol"' if freeze_first and i == 0 else ""
      # Add visual indicator for empty PID cells
      c_str = str(c)
      if freeze_first and i == 0 and not c_str.strip():
        cell_content = '<span style="color:#999; font-style:italic;">N/A</span>'
      else:
        cell_content = html.escape(c_str)
      tds.append(f"<td{cls}>{cell_content}</td>")
    body.append("<tr>" + "".join(tds) + "</tr>")
  # Tag Compact Stats tables (freeze_first=True) so we can size columns via CSS
  tbl_class = "tbl stats" if freeze_first else "tbl"
  return (
    f"<h2>{html.escape(title)}</h2>"
    f"<table class='{tbl_class}'><thead><tr>{thead}</tr></thead><tbody>{''.join(body)}</tbody></table>"
  )

ts=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
html_doc="""<!doctype html><meta charset="utf-8"><title>System Sanity Report</title>
<style>
 body{font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;margin:24px}
 .meta{color:#555;margin-bottom:16px}
 table.tbl{border-collapse:collapse;width:100%;margin:12px 0 32px;font-size:14px;table-layout:fixed}
 .tbl th,.tbl td{border:1px solid #ddd;padding:6px 8px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
 .tbl th{background:#f7f7f7;cursor:pointer;position:sticky;top:0;z-index:2}
.tbl td.firstcol{position:sticky;left:0;background:#fff;font-weight:600;z-index:1;max-width:450px}
.tbl tr:nth-child(even){background:#fafafa}
.tbl td:nth-child(1){max-width:80px;text-align:center;font-weight:600;color:#333}
 .tbl td:nth-child(2){max-width:100px;white-space:nowrap;text-overflow:ellipsis}
 /* Compact Stats column sizing: headers are [PID, Service, Counter, Min, Max, Average] */
 table.tbl.stats th:nth-child(3), /* Counter */
 table.tbl.stats td:nth-child(3){
   min-width: 40ch; /* make Counter ~2x wider */
   max-width: 72ch;
 }
 table.tbl.stats th:nth-child(4),
 table.tbl.stats td:nth-child(4),
 table.tbl.stats th:nth-child(5),
 table.tbl.stats td:nth-child(5),
 table.tbl.stats th:nth-child(6),
 table.tbl.stats td:nth-child(6){
   width: 9ch; /* tighten Min/Max/Average */
 }
 .tbl th .resize-handle{position:absolute;top:0;right:0;width:3px;height:100%;background:linear-gradient(to bottom,transparent,transparent 4px,#666 4px,#666 6px,transparent 6px);cursor:col-resize;opacity:0;transition:opacity 0.2s}
 .tbl th:hover .resize-handle{opacity:1}
 .tbl th .resize-handle:hover,.tbl th .resize-handle.dragging{opacity:1;background:linear-gradient(to bottom,transparent,transparent 4px,#007acc 4px,#007acc 6px,transparent 6px)}
 .hint{color:#666;font-size:12px;margin-top:-10px}
</style>
<h1>System Sanity Report</h1>
<div class="meta">Generated """ + html.escape(ts) + """ — Source: <code>""" + html.escape(outdir) + """</code></div>
<p class="hint">Click a column to sort. Double-click header to auto-fit. Drag resize handles on headers to resize columns. First column (PID) is frozen in Stats table.</p>
"""
# Aggregate: CPU by App (latest)
try:
  cpu_by_app = []
  if top and len(top) > 1:
    hdr = top[0]
    # Expect columns: [Instance, PID, CPU_ProcTime, SvcNames, SvcDisplayNames]
    inst_i = hdr.index("Instance") if "Instance" in hdr else 0
    cpu_i  = hdr.index("CPU_ProcTime") if "CPU_ProcTime" in hdr else 2
    groups = {}
    for r in top[1:]:
      if not r: continue
      inst = (r[inst_i] or "").split('#')[0]
      try:
        cpu = float(r[cpu_i])
      except:
        cpu = 0.0
      g = groups.get(inst)
      if not g:
        g = {"count":0, "cpu":0.0}
        groups[inst] = g
      g["count"] += 1
      g["cpu"] += cpu
    rows = [["App","ProcCount","TotalCPU_ProcTime"]]
    for app, g in groups.items():
      rows.append([app, str(g["count"]), f"{g['cpu']:.3f}"])
    # Sort by Total CPU desc
    rows_sorted = [rows[0]] + sorted(rows[1:], key=lambda x: float(x[2]), reverse=True)
    html_doc += table_html("CPU by App (latest)", rows_sorted)
except Exception:
  pass

# Aggregate: Browser CPU by Type (requires browser map)
try:
  browser_map = read_browser_proc_map()
  if browser_map and top and len(top) > 1:
    hdr = top[0]
    pid_i = hdr.index("PID") if "PID" in hdr else 1
    cpu_i = hdr.index("CPU_ProcTime") if "CPU_ProcTime" in hdr else 2
    groups = {}
    for r in top[1:]:
      if not r: continue
      pid = (r[pid_i] or "").strip()
      try:
        pid_i_val = int(pid)
      except:
        continue
      m = browser_map.get(pid_i_val)
      if not m: continue
      key = (m.get("browser") or "Browser", m.get("type") or "Unknown")
      try:
        cpu = float(r[cpu_i])
      except:
        cpu = 0.0
      g = groups.get(key)
      if not g:
        g = {"count":0, "cpu":0.0}
        groups[key] = g
      g["count"] += 1
      g["cpu"] += cpu
    rows = [["Browser","Type","ProcCount","TotalCPU_ProcTime"]]
    for (browser, typ), g in groups.items():
      rows.append([browser, typ, str(g["count"]), f"{g['cpu']:.3f}"])
    rows_sorted = [rows[0]] + sorted(rows[1:], key=lambda x: float(x[3]), reverse=True)
    html_doc += table_html("Browser CPU by Type (latest)", rows_sorted)
except Exception:
  pass

# Original detailed tables
html_doc += table_html("Top CPU (latest, with Services)", top)
html_doc += table_html("Compact Stats (PID / Service / Counter / Min / Max / Average)", stats, freeze_first=True)

html_doc += """
<script>
// Combined sorting and resizing functionality
let isDragging = false;
let startX = 0;
let startWidth = 0;
let currentResizeHandle = null;

document.querySelectorAll('table.tbl th').forEach((th)=>{
  th.style.position = 'relative';
  
  // Add resize handle (except for first column if you want)
  const handle = document.createElement('div');
  handle.className = 'resize-handle';
  th.appendChild(handle);

  // Sorting - click on header (but not on resize handle)
  th.addEventListener('click',(e)=>{
    if (e.target.classList.contains('resize-handle')) return; // ignore drag handle
    if (isDragging) return; // don't trigger sort while resizing

    const table = th.closest('table');
    const tbody = table.querySelector('tbody');
    if (!tbody) return;
    // Column index relative to this table (not the page-wide header index)
    const colIndex = Array.from(th.parentElement.children).indexOf(th);

    // Determine column types from header text (PID, Min, Max, Average => numeric)
    const headers = Array.from(table.querySelectorAll('thead th'));
    const types = headers.map(h => {
      const t = (h.textContent||'').trim().toLowerCase();
      return (t==='pid' || t==='min' || t==='max' || t==='average') ? 'num' : 'text';
    });

    const dir = th.dataset.dir = (th.dataset.dir === 'asc') ? 'desc' : 'asc';
    const rows = Array.from(tbody.querySelectorAll('tr'));

    function getText(tr, i){
      const cell = tr.children[i];
      return cell ? (cell.textContent||'').trim() : '';
    }
    function toVal(v, type){
      if (type === 'num'){
        const n = parseFloat(v.replace(/[^0-9.\-]/g,'').trim());
        return isNaN(n) ? Number.NEGATIVE_INFINITY : n;
      }
      return v.toLowerCase();
    }

    rows.sort((a,b)=>{
      const va = toVal(getText(a, colIndex), types[colIndex]||'text');
      const vb = toVal(getText(b, colIndex), types[colIndex]||'text');
      if (va < vb) return (dir==='asc') ? -1 : 1;
      if (va > vb) return (dir==='asc') ? 1 : -1;
      return 0;
    });

    rows.forEach(r => tbody.appendChild(r));
  });

  // Handle mousedown on resize handle
  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    isDragging = true;
    currentResizeHandle = handle;
    startX = e.clientX;
    startWidth = th.offsetWidth;
    handle.classList.add('dragging');
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  });

  // Double-click for auto-fit
  th.addEventListener('dblclick', (e) => {
    // Don't auto-fit if clicking on resize handle
    if (e.target.classList.contains('resize-handle')) return;
    
    const table = th.closest('table');
    const colIndex = Array.from(th.parentElement.children).indexOf(th);
    const cells = table.querySelectorAll(`tbody tr td:nth-child(${colIndex + 1})`);
    let maxWidth = 0;

    // Find maximum content width
    [th, ...cells].forEach(cell => {
      const tempDiv = document.createElement('div');
      tempDiv.style.position = 'absolute';
      tempDiv.style.visibility = 'hidden';
      tempDiv.style.whiteSpace = 'nowrap';
      tempDiv.style.fontSize = getComputedStyle(cell).fontSize;
      tempDiv.style.fontFamily = getComputedStyle(cell).fontFamily;
      tempDiv.style.padding = getComputedStyle(cell).padding;
      tempDiv.textContent = cell.textContent;
      document.body.appendChild(tempDiv);
      maxWidth = Math.max(maxWidth, tempDiv.offsetWidth);
      document.body.removeChild(tempDiv);
    });

    const newWidth = Math.max(80, maxWidth + 16);
    th.style.width = newWidth + 'px';
    table.querySelectorAll(`td:nth-child(${colIndex + 1})`).forEach(td => {
      td.style.width = newWidth + 'px';
    });
  });
});

// Global mouse events for resizing
document.addEventListener('mousemove', (e) => {
  if (!isDragging) return;

  const deltaX = e.clientX - startX;
  const newWidth = Math.max(50, startWidth + deltaX);

  const th = currentResizeHandle.parentElement;
  th.style.width = newWidth + 'px';

  const colIndex = Array.from(th.parentElement.children).indexOf(th) + 1;
  th.closest('table').querySelectorAll(`td:nth-child(${colIndex})`).forEach(td => {
    td.style.width = newWidth + 'px';
  });
});

document.addEventListener('mouseup', () => {
  if (!isDragging) return;

  isDragging = false;
  if (currentResizeHandle) {
    currentResizeHandle.classList.remove('dragging');
    currentResizeHandle = null;
  }
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
});
</script>
"""

with open(os.path.join(outdir,"report.html"),"w",encoding="utf-8") as f: f.write(html_doc)
print("Wrote: out/report.html")