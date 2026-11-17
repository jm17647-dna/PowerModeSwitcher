# -*- coding: utf-8 -*-
"""把 install.ps1 推到 GitHub（Contents API，单文件提交）。"""
import base64
import json
import os
import urllib.request
from pathlib import Path

OWNER, REPO = "jm17647-dna", "PowerModeSwitcher"
TOKEN = os.environ["GH_TOKEN"]
SRC = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher\install.ps1")
proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({"https": proxy, "http": proxy}) if proxy else urllib.request.ProxyHandler({})
)


def api(method, path, payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request("https://api.github.com" + path, data=body, method=method, headers={
        "Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json",
        "Content-Type": "application/json", "User-Agent": "pms-install-push"})
    with opener.open(req, timeout=45) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


data = SRC.read_bytes()
# 必须保留 BOM：PowerShell 5.1 按 ANSI 读取无 BOM 的 UTF-8 脚本，中文会乱码导致语法错误
if not data.startswith(b"\xef\xbb\xbf"):
    data = b"\xef\xbb\xbf" + data

payload = {
    "message": "feat: add install.ps1 one-click installer\n\n- 下载 AHK v2 便携运行时 + 仓库 zip，部署到 %LOCALAPPDATA%\\PowerModeSwitcher\n- 复用已安装的 AHK，避免重复下载\n- -NoStartup / -NoLaunch / -Mirror 参数\n- 已在本机实测：8 个文件落盘、启动后热键注册成功",
    "content": base64.b64encode(data).decode(),
    "branch": "main",
}

# 已存在则取 sha
try:
    cur = api("GET", f"/repos/{OWNER}/{REPO}/contents/install.ps1")
    payload["sha"] = cur["sha"]
    print("更新已有文件, sha =", cur["sha"][:8])
except Exception:
    print("新建文件")

res = api("PUT", f"/repos/{OWNER}/{REPO}/contents/install.ps1", payload)
print("commit =", res["commit"]["sha"][:8])
print("https://github.com/" + OWNER + "/" + REPO + "/blob/main/install.ps1")
