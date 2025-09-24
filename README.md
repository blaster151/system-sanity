# System Sanity Kit v0.1

This kit helps reclaim sanity on overloaded Windows machines by:

- Killing unnecessary background processes (Edge, vendor updaters)
- Starting and stopping a perfmon session
- Mapping `svchost` PIDs to services
- Optional: Mapping Chrome processes to tabs/extensions
- Enhanced process context (shows document names, window titles, application types)
- Cleaning perfmon CSV output for analysis

## Files

- `system-sanity.ps1`: Main triage script
- `perfmon_transform.py`: Transpose + average + sort CSV
- `chrome_debugger_extract.ps1`: Experimental Chrome PID mapper
- `profiles.json`: User-defined profiles for different scenarios
- `README.md`: You are here.

## Requirements

- PowerShell 5+
- Python 3
- Chrome (for tab mapping)

Run `system-sanity.ps1` from an elevated terminal to begin.

## Configuration

### Default Behavior

When no profile is specified, the system automatically uses the "normal" profile, which includes common background processes that are typically safe to terminate. You can customize this by editing the "normal" profile in `profiles.json`.

### Profiles

Create custom profiles in `profiles.json` for different scenarios (gaming, development, etc.). See the existing profiles for examples.

### Enhanced Process Context

The system now provides rich context information for processes:

- **Document Names**: Shows the name of documents being edited (Word, Excel, PowerPoint, Typora, Notepad++, etc.)
- **Application Types**: Identifies the purpose of processes (browser, code editor, markdown editor, etc.)
- **Window Titles**: Uses window titles as fallback context when command line parsing doesn't provide document names
- **Development Context**: For Node.js processes, shows ports, build tools, frameworks, and parent processes

Examples of context shown:
- `Typora (doc: README.md)` - Typora editing a specific markdown file
- `Code (workspace: my-project)` - VS Code with a specific workspace
- `node (serving :3000)` - Node.js development server
- `WINWORD (doc: report.docx)` - Word with a specific document

---

### Author: You!
