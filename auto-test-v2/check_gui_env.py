"""
Quick test script to verify GUI client can be imported
"""
import sys
from pathlib import Path

print("=" * 60)
print("Auto-Test V2 Desktop Client - Environment Check")
print("=" * 60)
print()

# Test 1: Python version
print("✓ Python version:", sys.version.split()[0])

# Test 2: Tkinter
try:
    import tkinter
    print("✓ Tkinter: Available")
except ImportError:
    print("✗ Tkinter: NOT AVAILABLE (required!)")
    sys.exit(1)

# Test 3: Core modules
try:
    from core.csv_parser import parse_csv_to_json
    from core.test_generator import TestScriptGenerator
    print("✓ Core modules: Available")
except ImportError as e:
    print(f"✗ Core modules: NOT AVAILABLE - {e}")
    print("  Make sure you're running from auto-test-v2 directory")
    sys.exit(1)

# Test 4: Dependencies
missing = []
try:
    import openai
except ImportError:
    missing.append("openai")

try:
    import pydantic
except ImportError:
    missing.append("pydantic")

try:
    from dotenv import load_dotenv
except ImportError:
    missing.append("python-dotenv")

if missing:
    print(f"⚠ Missing dependencies: {', '.join(missing)}")
    print("  Run: pip install -r requirements.txt")
else:
    print("✓ Dependencies: All installed")

print()
print("=" * 60)
if not missing:
    print("✅ Environment check PASSED - Ready to launch GUI!")
    print()
    print("To start the desktop client:")
    print("  1. Double-click: 启动测试客户端.bat")
    print("  2. Or run: python gui_client.py")
else:
    print("⚠️  Some dependencies missing - Install them first")
print("=" * 60)
