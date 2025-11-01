#!/usr/bin/env python3
"""
System Sanity Launcher
Modern Python-based launcher with beautiful CLI interface
"""

import subprocess
import sys
import os
from pathlib import Path

def main():
    """Launch System Sanity with proper environment"""
    script_path = Path(__file__).parent / "system-sanity.py"

    if not script_path.exists():
        print("❌ Error: system-sanity.py not found!")
        sys.exit(1)

    # Ensure we're in the correct directory
    os.chdir(script_path.parent)

    # Launch the main script
    try:
        subprocess.run([sys.executable, str(script_path)] + sys.argv[1:])
    except KeyboardInterrupt:
        print("\n🛑 Operation cancelled by user")
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
