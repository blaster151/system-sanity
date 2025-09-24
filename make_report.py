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
trans = read_csv("perf_transposed.csv")      # kept in case you still want full matrix

def table_html(title, rows, freeze_first=False):
    if not rows: return f"<h2>{html.escape(title)}</h2><p><em>No data</em></p>"
    head, data = rows[0], rows[1:]
    thead="".join(f"<th>{html.escape(h)}</th>" for h in head)
    body=[]
    for r in data:
        tds=[]
        for i,c in enumerate(r):
            cls=' class="firstcol"' if freeze_first and i==0 else ""
            # Add visual indicator for empty PID cells
            if freeze_first and i==0 and not c.strip():
                cell_content = '<span style="color:#999; font-style:italic;">N/A</span>'
            else:
                cell_content = html.escape(c)
            tds.append(f"<td{cls}>{cell_content}</td>")
        body.append("<tr>"+"".join(tds)+"</tr>")
    return f"<h2>{html.escape(title)}</h2><table class='tbl'><thead><tr>{thead}</tr></thead><tbody>{''.join(body)}</tbody></table>"

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
 .tbl th .resize-handle{position:absolute;top:0;right:0;width:3px;height:100%;background:linear-gradient(to bottom,transparent,transparent 4px,#666 4px,#666 6px,transparent 6px);cursor:col-resize;opacity:0;transition:opacity 0.2s}
 .tbl th:hover .resize-handle{opacity:1}
 .tbl th .resize-handle:hover,.tbl th .resize-handle.dragging{opacity:1;background:linear-gradient(to bottom,transparent,transparent 4px,#007acc 4px,#007acc 6px,transparent 6px)}
 .hint{color:#666;font-size:12px;margin-top:-10px}
</style>
<h1>System Sanity Report</h1>
<div class="meta">Generated """ + html.escape(ts) + """ — Source: <code>""" + html.escape(outdir) + """</code></div>
<p class="hint">Click a column to sort. Double-click header to auto-fit. Drag resize handles on headers to resize columns. First column is frozen in Stats and Transposed.</p>
""" + table_html("Top CPU (latest, with Services)", top) + """
""" + table_html("Compact Stats (PID / Counter / Min / Max / Average)", stats, freeze_first=True) + """
""" + table_html("Perf Transposed (raw samples; Average rightmost)", trans, freeze_first=True) + """
<script>
document.querySelectorAll('table.tbl th').forEach((th,idx)=>{
  th.addEventListener('click',()=>{
    const tb=th.closest('table').querySelector('tbody');
    const rows=[...tb.querySelectorAll('tr')];
    const num=v=>/^\\s*-?\\d+(\\.\\d+)?\\s*$/.test(v)?parseFloat(v):v.toLowerCase();
    const dir=th.dataset.dir=th.dataset.dir==='asc'?'desc':'asc';
    rows.sort((a,b)=>{
      const ta=a.children[idx]?.textContent||'', tbv=b.children[idx]?.textContent||'';
      const na=num(ta), nb=num(tbv);
      if(na<nb) return dir==='asc'?-1:1;
      if(na>nb) return dir==='asc'?1:-1;
      return 0;
    });
    rows.forEach(r=>tb.appendChild(r));
  });
});
</script>
"""

# Add column resizing JavaScript
resize_js = """
// Column resizing functionality
let isDragging = false;
let startX = 0;
let startWidth = 0;

document.querySelectorAll('table.tbl th').forEach((th,idx)=>{
  if (idx === 0) return; // Skip first column (frozen PID column)

  // Add resize handle
  const handle = document.createElement('div');
  handle.className = 'resize-handle';
  th.style.position = 'relative';
  th.appendChild(handle);

  // Handle mousedown on resize handle
  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    isDragging = true;
    startX = e.clientX;
    startWidth = th.offsetWidth;
    handle.classList.add('dragging');
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  });

  // Double-click for auto-fit
  th.addEventListener('dblclick', () => {
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

    const newWidth = Math.max(80, maxWidth + 16); // min 80px, add padding
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
  const newWidth = Math.max(50, startWidth + deltaX); // min 50px

  const th = document.querySelector('.resize-handle.dragging').parentElement;
  th.style.width = newWidth + 'px';

  // Apply to all cells in this column
  const colIndex = Array.from(th.parentElement.children).indexOf(th) + 1;
  th.closest('table').querySelectorAll(`td:nth-child(${colIndex})`).forEach(td => {
    td.style.width = newWidth + 'px';
  });
});

document.addEventListener('mouseup', () => {
  if (!isDragging) return;

  isDragging = false;
  document.querySelector('.resize-handle.dragging')?.classList.remove('dragging');
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
});
"""

html_doc += f"<script>{resize_js}</script>"
with open(os.path.join(outdir,"report.html"),"w",encoding="utf-8") as f: f.write(html_doc)
print("Wrote: out/report.html")