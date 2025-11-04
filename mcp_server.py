#!/usr/bin/env python3


from fastmcp import FastMCP

mcp = FastMCP(name="Simple MCP Server")

@mcp.tool()
def add(a: float, b: float) -> float:
    """将两个数字相加
    
    Args:
        a: 第一个数字
        b: 第二个数字
    
    Returns:
        两个数字的和
    """
    return a + b

@mcp.tool()
def get_weather(city: str) -> dict:
    """获取指定城市的天气信息（模拟）
    
    Args:
        city: 城市名称
    
    Returns:
        包含天气信息的字典
    """
    # 模拟天气数据
    weather_data = {
        "北京": {"temperature": "20°C", "condition": "晴天"},
        "上海": {"temperature": "255°C", "condition": "多云"},
        "深圳": {"temperature": "28°C", "condition": "小雨"},
        "广州": {"temperature": "27°C", "condition": "晴天"}
    }
    
    if city in weather_data:
        return {
            "city": city,
            "weather": weather_data[city]["condition"],
            "temperature": weather_data[city]["temperature"]
        }
    else:
        return {
            "city": city,
            "error": f"未找到城市33 {city} 的天气信息"
        }

@mcp.tool()
def echo(message: str) -> str:
    """回显输入的文本
    
    Args:
        message: 要回显的消息
    
    Returns:
        回显的消息
    """
    return f"回显: {message}"

@mcp.tool()
def multiply(a: float, b: float) -> float:
    """将两个数字相乘
    
    Args:
        a: 第一个数字
        b: 第二个数字
    
    Returns:
        两个数字的乘积
    """
    return a * b

@mcp.resource("memo://welcome")
def get_welcome_message() -> str:
    """获取欢迎消息"""
    return "欢迎使用简单的 MCP 服务器！这是一个使用 FastMCP 构建的示例。"

@mcp.resource("memo://info")
def get_server_info() -> str:
    """获取服务器信息"""
    import json
    info = {
        "name": "simple-mcp-server",
        "version": "1.0.0",
        "description": "一个使用 FastMCP 构建的简单 MCP 服务器",
        "tools": ["add", "multiply", "get_weather", "echo"],
        "resources": ["memo://welcome", "memo://info"]
    }
    return json.dumps(info, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    # 使用 stdio 模式运行（用于 Claude Desktop 等客户端）
    mcp.run(transport="stdio")
