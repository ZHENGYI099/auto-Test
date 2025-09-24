from __future__ import annotations
from typing import Dict

TRANSLATIONS: Dict[str, Dict[str, str]] = {
    'zh': {
        'brand': '测试用例转换平台',
        'upload_page_title': '上传 CSV - Test Case',
        'upload_heading': 'CSV 转 JSON 测试用例',
        'tool_badge': '工具',
        'upload_subtitle': '上传测试步骤 CSV，自动解析为结构化 JSON。',
        'csv_file': 'CSV 文件',
        'test_case_id_optional': 'Test Case ID (可选)',
        'convert_btn': '开始转换',
        'api_curl_title': 'cURL 调用示例',
        'copy': '复制',
        'copied': '已复制',
        'download_json': '下载 JSON',
        'convert_another': '再转换一个',
        'result_prefix': '转换结果',
        'steps_badge': '步骤',
        'collapse_expand_json': '折叠 / 展开 JSON',
        'steps_detail': '步骤明细',
        'json_preview': 'JSON 预览',
        'steps_count': '步骤数量',
        'doc': '文档',
        'upload_nav': '上传',
        'theme_toggle': '切换主题',
    },
    'en': {
        'brand': 'Test Case Converter',
        'upload_page_title': 'Upload CSV - Test Case',
        'upload_heading': 'CSV to JSON Test Case',
        'tool_badge': 'TOOL',
        'upload_subtitle': 'Upload a test step CSV and convert to structured JSON.',
        'csv_file': 'CSV File',
        'test_case_id_optional': 'Test Case ID (Optional)',
        'convert_btn': 'Convert',
        'api_curl_title': 'cURL Example',
        'copy': 'Copy',
        'copied': 'Copied',
        'download_json': 'Download JSON',
        'convert_another': 'Convert Another',
        'result_prefix': 'Result',
        'steps_badge': 'Steps',
        'collapse_expand_json': 'Collapse / Expand JSON',
        'steps_detail': 'Step Details',
        'json_preview': 'JSON Preview',
        'steps_count': 'Steps',
        'doc': 'Docs',
        'upload_nav': 'Upload',
        'theme_toggle': 'Toggle Theme',
    }
}

FALLBACK_LANG = 'en'


def get_translation(lang: str, key: str) -> str:
    table = TRANSLATIONS.get(lang) or TRANSLATIONS.get(FALLBACK_LANG, {})
    return table.get(key, key)

