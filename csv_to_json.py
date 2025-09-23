import csv, json, sys, os, argparse
from pathlib import Path

def parse_csv(path: str, test_case_id: str | None = None):
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"File not found: {p}")
    steps = []
    with p.open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        # Normalize header names (case-insensitive, strip)
        norm_map = {h: h.strip().lower() for h in reader.fieldnames or []}
        # Expect keys like steps, action, expect result
        for row in reader:
            if not row:
                continue
            # Access with possible variants
            step_raw = row.get('Steps') or row.get('steps') or row.get('Step') or row.get('STEP')
            if step_raw is None or str(step_raw).strip() == '':
                continue
            try:
                step_no = int(str(step_raw).strip())
            except ValueError:
                continue
            action = row.get('Action') or row.get('action') or ''
            expected = row.get('Expect result') or row.get('Expect Result') or row.get('expect result') or row.get('Expected') or row.get('expected') or ''
            steps.append({
                'step': step_no,
                'action': action.strip(),
                'expected': expected.strip(),
            })
    # Sort by step number to ensure order
    steps.sort(key=lambda x: x['step'])
    return {
        'test_case_id': test_case_id or p.stem,
        'steps': steps
    }


def main():
    ap = argparse.ArgumentParser(description='Convert test case CSV to JSON structure.')
    ap.add_argument('csv_path', help='Path to CSV file')
    ap.add_argument('--id', dest='case_id', help='Override test_case_id')
    ap.add_argument('--out', dest='out_path', help='Write JSON to file path (e.g. output.json)')
    args = ap.parse_args()
    data = parse_csv(args.csv_path, args.case_id)
    output = json.dumps(data, ensure_ascii=False, indent=2)
    if args.out_path:
        out_p = Path(args.out_path)
        out_p.write_text(output, encoding='utf-8')
        print(f"Saved JSON to {out_p.resolve()}")
    else:
        print(output)

if __name__ == '__main__':
    main()
