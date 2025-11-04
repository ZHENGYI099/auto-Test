"""测试无密钥认证方式的 ModelClient（强制 Azure AD Token）"""
from dotenv import load_dotenv
from core.model_client import ModelClient

# 加载 .env 文件中的环境变量
load_dotenv()

print("🔐 使用 Azure AD 无密钥认证")

try:
    client = ModelClient()
    print(f"✅ ModelClient 初始化成功，部署: {client.deployment}")
    
    response = client.chat(
        system="你是一个有用的助手。",
        user="测试无密钥调用是否成功？",
        max_tokens=100
    )
    
    print("\n--- 响应内容 ---")
    print(response)
    print("\n✅ 测试成功！")
    
except Exception as e:
    print(f"\n❌ 测试失败: {e}")
    import traceback
    traceback.print_exc()
