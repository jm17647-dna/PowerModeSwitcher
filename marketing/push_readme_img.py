# -*- coding: utf-8 -*-
"""在远程 README.md 里插入小红书宣传图区块（基于远程原文，不引入本地 v1.1 内容）。"""
import base64
import json
import os
import urllib.request

OWNER, REPO, BRANCH = "jm17647-dna", "PowerModeSwitcher", "main"
TOKEN = os.environ["GH_TOKEN"]
proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
op = urllib.request.build_opener(
    urllib.request.ProxyHandler({"https": proxy, "http": proxy}) if proxy else urllib.request.ProxyHandler({})
)


def api(method, path, payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request("https://api.github.com" + path, data=body, method=method, headers={
        "Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json",
        "Content-Type": "application/json", "User-Agent": "pms-readme"})
    with op.open(req, timeout=120) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


cur = api("GET", f"/repos/{OWNER}/{REPO}/contents/README.md?ref={BRANCH}")
txt = base64.b64decode(cur["content"]).decode("utf-8")
print("remote README:", len(txt), "chars, sha", cur["sha"][:8])

BLOCK = """## 宣传图

小红书用的 9 张竖版宣传图（1080×1440），点开看大图：

[![宣传图预览](marketing/xiaohongshu/preview.png)](marketing/xiaohongshu/)

文案与发布说明见 [`marketing/xiaohongshu/文案.md`](marketing/xiaohongshu/)，渲染脚本是 [`marketing/render_xhs.py`](marketing/render_xhs.py)。

---

## 界面"""

anchor = "---\n\n## 界面"
if BLOCK.split("## 界面")[0].strip() and "## 宣传图" in txt:
    raise SystemExit("README 里已经有宣传图区块了，先删掉再加")

if anchor not in txt:
    raise SystemExit("找不到插入锚点 '---\\n\\n## 界面'，未修改")

new_txt = txt.replace(anchor, BLOCK, 1)
print("插入完成，新长度:", len(new_txt))

res = api("PUT", f"/repos/{OWNER}/{REPO}/contents/README.md", {
    "message": "docs: add Xiaohongshu promo preview to README",
    "content": base64.b64encode(new_txt.encode("utf-8")).decode(),
    "sha": cur["sha"],
    "branch": BRANCH,
})
print("commit:", res["commit"]["sha"][:8])

chk = api("GET", f"/repos/{OWNER}/{REPO}/contents/README.md?ref={BRANCH}")
back = base64.b64decode(chk["content"]).decode("utf-8")
print("回读验证: 含'## 宣传图' =", "## 宣传图" in back,
      "| 含 preview.png =", "xiaohongshu/preview.png" in back,
      "| 长度", len(back))
print("DONE https://github.com/%s/%s" % (OWNER, REPO))
