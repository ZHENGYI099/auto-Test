import os, sys, json, base64, argparse

sys.path.append(os.path.dirname(os.path.dirname(__file__)))

try:
	from dotenv import load_dotenv  # type: ignore
except Exception:
	def load_dotenv():
		return False

from core.model_client import ModelClient
from core.prompts import VISION_SIMPLE_PROMPT_TEMPLATE


def _b64(path: str) -> str:
	with open(path, 'rb') as f:
		return base64.b64encode(f.read()).decode('utf-8')


def _build_prompt(expected: str) -> str:
	return VISION_SIMPLE_PROMPT_TEMPLATE.format(expected=expected)


def _call(img_b64: str, prompt: str, override: str | None) -> str:
	model = ModelClient()
	if override:
		model.deployment = override
	messages = [
		{
			'role': 'user',
			'content': [
				{'type': 'text', 'text': prompt},
				{'type': 'image_url', 'image_url': {'url': f'data:image/png;base64,{img_b64}'}}
			]
		}
	]
	return model.chat_messages(messages, temperature=0.0, max_tokens=300)


def _extract(raw: str) -> dict:
	import re
	m = re.search(r"\{.*\}", raw, re.DOTALL)
	if m:
		try:
			data = json.loads(m.group(0))
			if isinstance(data, dict) and 'status' in data:
				return data
		except Exception:
			pass
	return {"status": "fail", "reason": "Unparseable model output", "raw": raw[:400]}


def _out_path(caseid: str, step: str, explicit: str) -> str:
	if explicit:
		return explicit
	caseid = caseid.strip() or 'unknownCase'
	step = step.strip() or 'unknownStep'
	raw_name = f"{caseid}_{step}_VerifyResult.json"
	# Remove or replace any remaining invalid characters for Windows filenames
	invalid = '<>:"/\\|?*'
	safe = ''.join(c if c not in invalid else '_' for c in raw_name)
	out_dir = os.path.join(os.getcwd(), 'outputs')
	os.makedirs(out_dir, exist_ok=True)
	return os.path.join(out_dir, safe)


def main():
	p = argparse.ArgumentParser(description='Vision verification (image -> JSON)')
	p.add_argument('--image', required=True)
	p.add_argument('--expect', required=True)
	p.add_argument('--caseid', default='')
	p.add_argument('--step', default='')
	p.add_argument('--json-out', default='')
	args = p.parse_args()

	load_dotenv()

	if not os.path.exists(args.image):
		data = {"status": "fail", "reason": f"Image not found: {args.image}"}
		path = _out_path(args.caseid, args.step, args.json_out)
		with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, ensure_ascii=False, indent=2)
		print(json.dumps(data, ensure_ascii=False))
		sys.exit(1)

	expected = args.expect.strip()
	if not expected:
		data = {"status": "fail", "reason": "Missing --expect"}
		path = _out_path(args.caseid, args.step, args.json_out)
		with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, ensure_ascii=False, indent=2)
		print(json.dumps(data, ensure_ascii=False))
		sys.exit(1)

	try:
		prompt = _build_prompt(expected)
		raw = _call(_b64(args.image), prompt, os.getenv('AZURE_OPENAI_DEPLOYMENT_VISION'))
		data = _extract(raw)
		status = str(data.get('status','')).lower()
		if status not in ('success','fail'):
			data['status'] = 'fail'
			data.setdefault('reason', 'Unexpected model format')
		path = _out_path(args.caseid, args.step, args.json_out)
		with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, ensure_ascii=False, indent=2)
		print(json.dumps(data, ensure_ascii=False))
		sys.exit(0 if data['status'] == 'success' else 1)
	except RuntimeError as re_err:
		data = {"status": "fail", "reason": f"RuntimeError: {re_err}"}
		path = _out_path(args.caseid, args.step, args.json_out)
		with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, ensure_ascii=False, indent=2)
		print(json.dumps(data, ensure_ascii=False))
		sys.exit(1)
	except Exception as e:
		data = {"status": "fail", "reason": f"Unhandled error: {type(e).__name__}: {e}"}
		path = _out_path(args.caseid, args.step, args.json_out)
		with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, ensure_ascii=False, indent=2)
		print(json.dumps(data, ensure_ascii=False))
		sys.exit(1)


if __name__ == '__main__':
	main()
