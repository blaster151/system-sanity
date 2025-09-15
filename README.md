# System Sanity Kit v0.1

This kit helps reclaim sanity on overloaded Windows machines by:

- Killing unnecessary background processes (Edge, vendor updaters)
- Starting and stopping a perfmon session
- Mapping `svchost` PIDs to services
- Optional: Mapping Chrome processes to tabs/extensions
- Cleaning perfmon CSV output for analysis

## Files

- `system-sanity.ps1`: Main triage script
- `perfmon_transform.py`: Transpose + average + sort CSV
- `chrome_debugger_extract.ps1`: Experimental Chrome PID mapper
- `README.md`: You are here.

## Requirements

- PowerShell 5+
- Python 3
- Chrome (for tab mapping)

Run `system-sanity.ps1` from an elevated terminal to begin.

---

### Author: You!
