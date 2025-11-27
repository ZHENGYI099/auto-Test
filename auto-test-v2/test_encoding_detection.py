"""
测试日志文件编码检测
"""
from pathlib import Path

def detect_file_encoding(file_path):
    """
    检测文件编码并读取内容
    """
    encodings = ['utf-16-le', 'utf-16', 'utf-8', 'gbk', 'latin-1']
    
    print(f"\n🔍 Testing file: {file_path}")
    print("=" * 60)
    
    # 读取前几个字节检查 BOM
    with open(file_path, 'rb') as f:
        bom = f.read(4)
    
    print(f"BOM bytes: {' '.join(f'{b:02x}' for b in bom[:4])}")
    
    if bom[:2] == b'\xff\xfe':
        print("✓ Detected UTF-16 LE BOM")
    elif bom[:2] == b'\xfe\xff':
        print("✓ Detected UTF-16 BE BOM")
    elif bom[:3] == b'\xef\xbb\xbf':
        print("✓ Detected UTF-8 BOM")
    else:
        print("⚠ No standard BOM found")
    
    print("\n📖 Trying encodings:")
    print("-" * 60)
    
    for encoding in encodings:
        try:
            with open(file_path, 'r', encoding=encoding) as f:
                content = f.read()
            print(f"✅ {encoding:15s} - SUCCESS ({len(content)} chars)")
            print(f"   Preview: {content[:100].strip()[:80]}...")
            return encoding, content
        except (UnicodeDecodeError, UnicodeError) as e:
            print(f"❌ {encoding:15s} - FAILED: {str(e)[:50]}")
    
    # Fallback
    print("\n⚠️ All encodings failed, using UTF-8 with error replacement")
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    return 'utf-8-replace', content


if __name__ == "__main__":
    # Test with latest log file
    log_dir = Path(__file__).parent / "output" / "logs"
    
    if not log_dir.exists():
        print(f"❌ Log directory not found: {log_dir}")
        exit(1)
    
    log_files = sorted(log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    
    if not log_files:
        print(f"❌ No log files found in: {log_dir}")
        exit(1)
    
    print(f"\n📁 Found {len(log_files)} log file(s)")
    print("=" * 60)
    
    # Test the latest log
    latest_log = log_files[0]
    encoding, content = detect_file_encoding(latest_log)
    
    print("\n" + "=" * 60)
    print(f"✅ Best encoding: {encoding}")
    print(f"📄 Content length: {len(content)} characters")
    print("=" * 60)
