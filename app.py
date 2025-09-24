import os
from pathlib import Path
from flask import Flask, request, render_template, redirect, url_for, flash, send_file, jsonify, make_response, g
from werkzeug.utils import secure_filename
import json

from csv_to_json import parse_csv
from i18n import get_translation

UPLOAD_DIR = Path('uploads')
OUTPUT_DIR = Path('outputs')
UPLOAD_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)

ALLOWED_EXT = {'.csv'}

app = Flask(__name__)
app.config['SECRET_KEY'] = 'replace-me'
app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024  # 5MB


def allowed(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_EXT


def _resolve_lang() -> str:
    q = request.args.get('lang')
    if q: return q[:5]
    c = request.cookies.get('lang')
    if c: return c[:5]
    return 'zh'

@app.before_request
def _set_lang():
    g.lang = _resolve_lang()

@app.context_processor
def inject_t():
    lang = getattr(g, 'lang', 'zh')
    def t(key: str):
        return get_translation(lang, key)
    return {'t': t, 'lang': lang}

@app.route('/set-lang/<lang>')
def set_lang(lang: str):
    resp = make_response(redirect(request.referrer or url_for('index')))
    resp.set_cookie('lang', lang, max_age=60*60*24*365)
    return resp

@app.route('/', methods=['GET'])
def index():
    return render_template('upload.html')


@app.route('/api/convert', methods=['POST'])
def api_convert():
    file = request.files.get('file')
    case_id = request.form.get('testcaseid', '').strip()
    if not file or file.filename == '':
        flash('No file provided')
        return redirect(url_for('index'))
    if not allowed(file.filename):
        flash('Unsupported file type (only .csv)')
        return redirect(url_for('index'))
    safe_name = secure_filename(file.filename)
    saved_path = UPLOAD_DIR / safe_name
    file.save(saved_path)
    try:
        data = parse_csv(str(saved_path), case_id or None)
    except SystemExit as e:
        flash(str(e))
        return redirect(url_for('index'))
    json_name = f"{data['test_case_id']}.json"
    out_path = OUTPUT_DIR / json_name
    out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    return render_template('result.html', data=data, download_name=json_name)


@app.route('/download/<name>')
def download(name):
    target = OUTPUT_DIR / name
    if not target.exists():
        flash('File not found')
        return redirect(url_for('index'))
    return send_file(target, as_attachment=True, download_name=name)


# Simple JSON API endpoint (AJAX usage)
@app.route('/api/convert/json', methods=['POST'])
def api_convert_json():
    file = request.files.get('file')
    case_id = request.form.get('testcaseid', '').strip()
    if not file or file.filename == '':
        return jsonify({'error': 'No file provided'}), 400
    if not allowed(file.filename):
        return jsonify({'error': 'Unsupported file type'}), 400
    safe_name = secure_filename(file.filename)
    saved_path = UPLOAD_DIR / safe_name
    file.save(saved_path)
    try:
        data = parse_csv(str(saved_path), case_id or None)
    except SystemExit as e:
        return jsonify({'error': str(e)}), 400
    return jsonify(data)


if __name__ == '__main__':
    port = int(os.environ.get('PORT', '5000'))
    app.run(host='0.0.0.0', port=port, debug=True)
