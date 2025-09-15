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
            tds.append(f"<td{cls}>{html.escape(c)}</td>")
        body.append("<tr>"+"".join(tds)+"</tr>")
    return f"<h2>{html.escape(title)}</h2><table class='tbl'><thead><tr>{thead}</tr></thead><tbody>{''.join(body)}</tbody></table>"

ts=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
html_doc=f"""<!doctype html><meta charset="utf-8"><title>System Sanity Report</title>
<style>
 body{{font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;margin:24px}}
 .meta{{color:#555;margin-bottom:16px}}
 table.tbl{{border-collapse:collapse;width:100%;margin:12px 0 32px;font-size:14px;table-layout:fixed}}
 .tbl th,.tbl td{{border:1px solid #ddd;padding:6px 8px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}}
 .tbl th{{background:#f7f7f7;cursor:pointer;position:sticky;top:0;z-index:2}}
 .tbl td.firstcol{{position:sticky;left:0;background:#fff;font-weight:600;z-index:1;max-width:520px}}
 .tbl tr:nth-child(even){{background:#fafafa}}
 .hint{{color:#666;font-size:12px;margin-top:-10px}}
</style>
<h1>System Sanity Report</h1>
<div class="meta">Generated {html.escape(ts)} — Source: <code>{html.escape(outdir)}</code></div>
<p class="hint">Click a column to sort. First column is frozen in Stats and Transposed.</p>
{table_html("Top CPU (latest, with Services)", top)}
{table_html("Compact Stats (Min / Max / Average)", stats, freeze_first=True)}
{table_html("Perf Transposed (raw samples; Average rightmost)", trans, freeze_first=True)}
<script>
document.querySelectorAll('table.tbl th').forEach((th,idx)=>{{
  th.addEventListener('click',()=>{{
    const tb=th.closest('table').querySelector('tbody');
    const rows=[...tb.querySelectorAll('tr')];
    const num=v=>/^\\s*-?\\d+(\\.\\d+)?\\s*$/.test(v)?parseFloat(v):v.toLowerCase();
    const dir=th.dataset.dir=th.dataset.dir==='asc'?'desc':'asc';
    rows.sort((a,b)=>{{
      const ta=a.children[idx]?.textContent||'', tbv=b.children[idx]?.textContent||'';
      const na=num(ta), nb=num(tbv);
      if(na<nb) return dir==='asc'?-1:1;
      if(na>nb) return dir==='asc'?1:-1;
      return 0;
    }});
    rows.forEach(r=>tb.appendChild(r));
  }});
}});
</script>"""
with open(os.path.join(outdir,"report.html"),"w",encoding="utf-8") as f: f.write(html_doc)
print("Wrote: out/report.html")