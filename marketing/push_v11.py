# -*- coding: utf-8 -*-
"""增量推送 v1.1 + 小红书营销材料到 GitHub（git data API，带 base_tree）。"""
import base64
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

OWNER, REPO, BRANCH = "jm17647-dna", "PowerModeSwitcher", "main"
TOKEN = os.environ["GH_TOKEN"]
PROJ = Path(r"D:\WorkBuddy\空间\04-系统工具与归档\PowerModeSwitcher")
proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({"https": proxy, "http": proxy}) if proxy else urllib.request.ProxyHandler({})
)

FILES = [
    "marketing/xiaohongshu/_ai_bg_red.jpg",
    "marketing/xiaohongshu/_ai_bg_blue.jpg",
    "marketing/xiaohongshu/_ai_bg_purple.jpg",
    "marketing/xiaohongshu/_icon_badge.png",
    "marketing/xiaohongshu/_osd_strip.png",
]


def api(method, path, payload=None, retries=3, timeout=180):
    url = "https://api.github.com" + path
    body = json.dumps(payload).encode() if payload is not None else None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, data=body, method=method, headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "pms-sync",
        })
        try:
            with opener.open(req, timeout=timeout) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            if e.code in (401, 403, 404):
                raise SystemExit(f"HTTP {e.code}: {detail}")
            if attempt == retries:
                raise SystemExit(f"{method} {path} -> HTTP {e.code}: {detail}")
            print(f"  retry {attempt}: HTTP {e.code}")
        except Exception as e:
            if attempt == retries:
                raise SystemExit(f"{method} {path} -> {type(e).__name__}: {e}")
            print(f"  retry {attempt}: {type(e).__name__}")
    return {}


me = api("GET", "/user")
print("auth ok:", me.get("login"))

ref = api("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}")
head = ref["object"]["sha"]
commit = api("GET", f"/repos/{OWNER}/{REPO}/git/commits/{head}")
base_tree = commit["tree"]["sha"]
print("head:", head[:8], "| base tree:", base_tree[:8])

entries, missing, total = [], [], 0
for rel in FILES:
    p = PROJ / rel
    if not p.exists():
        missing.append(rel)
        print("  SKIP (missing):", rel)
        continue
    data = p.read_bytes()
    total += len(data)
    b = api("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
            {"content": base64.b64encode(data).decode(), "encoding": "base64"})
    entries.append({"path": rel.replace("\\", "/"), "mode": "100644", "type": "blob", "sha": b["sha"]})
    print(f"  {len(data)/1024:8.1f} KB  {rel}")

print(f"uploaded {len(entries)} files, {total/1048576:.2f} MB")
if missing:
    print("missing:", missing)

tree = api("POST", f"/repos/{OWNER}/{REPO}/git/trees", {"base_tree": base_tree, "tree": entries})
print("new tree:", tree["sha"][:8])

msg = ("docs(marketing): add Xiaohongshu source assets\n\n"
       "- AI-generated background plates used by render_xhs.py\n"
       "- product icon badge and OSD strip composite\n"
       "- project files untouched")
new_commit = api("POST", f"/repos/{OWNER}/{REPO}/git/commits",
                 {"message": msg, "tree": tree["sha"], "parents": [head]})
print("commit:", new_commit["sha"][:8])

api("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}",
    {"sha": new_commit["sha"], "force": False})
print("ref updated")

verify = api("GET", f"/repos/{OWNER}/{REPO}/git/trees/{BRANCH}?recursive=1")
blobs = [t["path"] for t in verify["tree"] if t["type"] == "blob"]
print("remote files:", len(blobs))
for key in ["Lib/UIA.ahk", "marketing/xiaohongshu/01.png", "marketing/xiaohongshu/文案.md",
            "PowerModeSwitcher.ahk", "docs/overlay-节能联动说明.md"]:
    print("  ", "OK " if key in blobs else "MISS", key)
print("DONE https://github.com/%s/%s" % (OWNER, REPO))
