#!/usr/bin/env python3
"""统计单个 Claude Code 会话的 token 消耗，并生成可视化 HTML。

用法:
    python3 Tools/analyze-session-tokens.py <session-id-prefix> [-o out.html]
    python3 Tools/analyze-session-tokens.py --list

口径说明（三个数不是一回事，别混）:
    total  = 该轮所有 API 调用的 (input + cache_creation + cache_read + output) 之和。
             同一段历史被每次调用重复读入，所以它远大于会话真实文本量。
    calls  = 该轮去重后的 API 调用次数（按 message.id 去重；一条响应会在
             jsonl 里拆成多行，不去重会翻倍）。
    ctx    = 该轮单次调用读入的最大上下文 = max(input + cache_creation + cache_read)。
             这才是"上下文越聊越大"对应的指标。
    out    = 该轮输出 token 之和。

subagent（Agent 工具派出去的）用量记在 <session>/subagents/*.jsonl，
按 meta.json 里的 toolUseId 归到发起它的那一轮。默认计入，可用 --no-subagents 排除。
"""

import argparse
import glob
import json
import os
import sys

PROJECTS = os.path.expanduser("~/.claude/projects")


def project_dir(cwd=None):
    cwd = cwd or os.getcwd()
    return os.path.join(PROJECTS, cwd.replace("/", "-"))


def load(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def text_of(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    parts = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
    return "\n".join(parts)


def is_real_prompt(entry):
    """真正由用户提交的一轮，排除 tool_result、meta 附件、系统注入。"""
    if entry.get("type") != "user" or entry.get("isSidechain") or entry.get("isMeta"):
        return False
    msg = entry.get("message") or {}
    c = msg.get("content")
    if isinstance(c, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_result" for b in c
    ):
        return False
    t = text_of(msg).strip()
    if not t:
        return False
    for marker in ("<task-notification>", "<local-command-", "<command-name>", "Caveat:"):
        if t.startswith(marker):
            return False
    # 只剩 system-reminder 的也不算
    if t.startswith("<system-reminder>") and t.endswith("</system-reminder>"):
        return False
    return True


def usage_sum(u):
    return (
        u.get("input_tokens", 0)
        + u.get("cache_creation_input_tokens", 0)
        + u.get("cache_read_input_tokens", 0)
        + u.get("output_tokens", 0)
    )


def usage_ctx(u):
    return (
        u.get("input_tokens", 0)
        + u.get("cache_creation_input_tokens", 0)
        + u.get("cache_read_input_tokens", 0)
    )


def accumulate(entries, bucket, seen):
    """把 assistant 条目按 message.id 去重后累加进 bucket。"""
    for e in entries:
        if e.get("type") != "assistant":
            continue
        msg = e.get("message") or {}
        mid = msg.get("id")
        u = msg.get("usage") or {}
        if not u or not mid or mid in seen:
            continue
        seen.add(mid)
        bucket["total"] += usage_sum(u)
        bucket["out"] += u.get("output_tokens", 0)
        bucket["calls"] += 1
        bucket["ctx"] = max(bucket["ctx"], usage_ctx(u))


def analyze(session_path, include_subagents=True):
    entries = load(session_path)
    base = session_path[: -len(".jsonl")]
    sub_by_tool = {}
    if include_subagents:
        for meta_path in sorted(glob.glob(os.path.join(base, "subagents", "*.meta.json"))):
            meta = json.loads(open(meta_path, encoding="utf-8").read())
            jsonl = meta_path.replace(".meta.json", ".jsonl")
            if os.path.exists(jsonl):
                sub_by_tool.setdefault(meta.get("toolUseId"), []).append((meta, jsonl))

    turns = []
    cur = None
    seen = set()

    def new_turn(prompt):
        return {
            "n": len(turns) + 1,
            "q": prompt,
            "total": 0,
            "out": 0,
            "calls": 0,
            "ctx": 0,
            "sub_total": 0,
            "sub_calls": 0,
            "sub_names": [],
            "start": None,
        }

    for e in entries:
        if is_real_prompt(e):
            cur = new_turn(" ".join(text_of(e["message"]).split()))
            cur["start"] = e.get("timestamp")
            turns.append(cur)
            continue
        if cur is None:
            continue
        accumulate([e], cur, seen)
        # subagent 归属：这一轮里出现的 tool_use id
        msg = e.get("message") or {}
        if e.get("type") == "assistant" and isinstance(msg.get("content"), list):
            for b in msg["content"]:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    for meta, jsonl in sub_by_tool.pop(b.get("id"), []):
                        sb = {"total": 0, "out": 0, "calls": 0, "ctx": 0}
                        accumulate(load(jsonl), sb, set())
                        cur["sub_total"] += sb["total"]
                        cur["sub_calls"] += sb["calls"]
                        cur["sub_names"].append(
                            f"{meta.get('agentType')}: {meta.get('description')}"
                        )
                        cur["total"] += sb["total"]
                        cur["out"] += sb["out"]
                        cur["calls"] += sb["calls"]
    return turns, sub_by_tool


TEMPLATE_HEAD = """<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">
<title>会话 token 消耗趋势</title>
<style>
:root{color-scheme:light dark}
body{margin:0;background:var(--page);font:14px/1.55 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}
.viz-root{
  color-scheme:light;
  --page:#f4f4f2; --surface-1:#fcfcfb; --text-primary:#0b0b0b; --text-secondary:#52514e;
  --text-muted:#8a8880; --grid:#e6e5e1; --series-1:#2a78d6; --series-2:#eb6834;
}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])) .viz-root{
  color-scheme:dark;
  --page:#111110; --surface-1:#1a1a19; --text-primary:#fff; --text-secondary:#c3c2b7;
  --text-muted:#8a8880; --grid:#2e2e2b; --series-1:#3987e5; --series-2:#d95926;}}
:root[data-theme="dark"] .viz-root{
  color-scheme:dark;
  --page:#111110; --surface-1:#1a1a19; --text-primary:#fff; --text-secondary:#c3c2b7;
  --text-muted:#8a8880; --grid:#2e2e2b; --series-1:#3987e5; --series-2:#d95926;}
.viz-root{background:var(--page);min-height:100vh;padding:28px 30px 40px}
.wrap{max-width:1000px;margin:0 auto}
h1{font-size:19px;font-weight:650;color:var(--text-primary);margin:0 0 4px}
.sub{color:var(--text-secondary);font-size:12.5px;margin:0 0 4px}
.hero{display:flex;gap:34px;margin:20px 0 26px;flex-wrap:wrap}
.tile{background:var(--surface-1);border:1px solid var(--grid);border-radius:11px;padding:13px 17px;min-width:150px}
.tile .k{font-size:11px;color:var(--text-muted);margin-bottom:5px}
.tile .v{font-size:23px;font-weight:660;color:var(--text-primary);font-variant-numeric:tabular-nums;letter-spacing:-.4px}
.tile .n{font-size:11px;color:var(--text-secondary);margin-top:3px}
.card{background:var(--surface-1);border:1px solid var(--grid);border-radius:13px;padding:17px 19px 9px;margin-bottom:17px}
.ct{font-size:14px;font-weight:620;color:var(--text-primary);margin:0 0 2px}
.cs{font-size:11.5px;color:var(--text-secondary);margin:0 0 11px}
svg{display:block;width:100%;overflow:visible}
.gl{stroke:var(--grid);stroke-width:1}
.ax{fill:var(--text-muted);font-size:10.5px;font-variant-numeric:tabular-nums}
.dl{fill:var(--text-secondary);font-size:10.5px;font-variant-numeric:tabular-nums}
.hit{fill:transparent;cursor:crosshair}
.cross{stroke:var(--text-muted);stroke-width:1;stroke-dasharray:3 3;opacity:0;pointer-events:none}
.tip{position:fixed;pointer-events:none;opacity:0;transition:opacity .09s;background:var(--surface-1);
 border:1px solid var(--grid);border-radius:9px;padding:9px 11px;font-size:11.5px;color:var(--text-primary);
 box-shadow:0 7px 22px rgba(0,0,0,.17);z-index:9;max-width:270px}
.tip b{font-weight:640}.tip .q{color:var(--text-secondary);font-size:10.5px;display:block;margin-top:4px;line-height:1.4}
table{border-collapse:collapse;width:100%;font-size:11.5px;font-variant-numeric:tabular-nums}
th,td{text-align:right;padding:5px 7px;border-bottom:1px solid var(--grid);color:var(--text-secondary)}
th{color:var(--text-muted);font-weight:520}
td:nth-child(2),th:nth-child(2){text-align:left;color:var(--text-primary);max-width:340px;
 overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
details{margin-top:5px}summary{cursor:pointer;color:var(--text-secondary);font-size:12px;padding:5px 0}
.tog{position:fixed;top:15px;right:18px;background:var(--surface-1);border:1px solid var(--grid);
 border-radius:7px;padding:5px 11px;font-size:11.5px;color:var(--text-secondary);cursor:pointer}
</style></head>
<body><div class="viz-root"><div class="wrap">
<button class="tog" onclick="var r=document.documentElement;r.dataset.theme=r.dataset.theme==='dark'?'light':'dark'">切换深浅</button>
<h1>会话 token 消耗趋势</h1>
<p class="sub">__SUB__</p>
<div class="hero" id="hero"></div>

<div class="card">
<p class="ct">单次 API 调用读入的上下文</p>
<p class="cs">每次调用要重新读一遍全部历史。这条线单调上升 —— 你的直觉是对的，但对的是这个指标。</p>
<svg id="c2" viewBox="0 0 940 250"></svg></div>

<div class="card">
<p class="ct">每轮消耗的 token 总量</p>
<p class="cs">柱状而非折线：各轮之间没有连续性，相邻两轮的插值没有意义。这条<b>不随轮次上升</b> —— 决定它的是那一轮调了多少次工具。</p>
<svg id="c1" viewBox="0 0 940 250"></svg></div>

<details open><summary>数据表</summary>
<table id="tbl"><thead><tr><th>轮次</th><th>提问</th><th>总 token</th><th>工具调用</th><th>单次上下文</th><th>输出</th><th>其中 subagent</th></tr></thead><tbody></tbody></table>
</details>
</div></div>
<div class="tip" id="tip"></div>
<script>
const D=__DATA__;
"""

TEMPLATE_TAIL = r"""
const fmt=n=>n>=1e6?(n/1e6).toFixed(1)+'M':n>=1e3?Math.round(n/1e3)+'k':n;
const tip=document.getElementById('tip');
const L=64,R=18,T=14,B=30,W=940,H=250,iw=W-L-R,ih=H-T-B;
const TOT=D.reduce((a,b)=>a+b.total,0),OUT=D.reduce((a,b)=>a+b.out,0);

document.getElementById('hero').innerHTML=[
 ['全会话总量',fmt(TOT),'含缓存重复读入'],
 ['单次上下文增幅',D.length>1?'+'+Math.round((D.at(-1).ctx/D[0].ctx-1)*100)+'%':'—',
   fmt(D[0].ctx)+' → '+fmt(D.at(-1).ctx)],
 ['工具调用总数',D.reduce((a,b)=>a+b.calls,0),'每次都重读全部上下文'],
 ['模型输出总量',fmt(OUT),'仅占总量 '+(OUT/TOT*100).toFixed(1)+'%']
].map(t=>`<div class="tile"><div class="k">${t[0]}</div><div class="v">${t[1]}</div><div class="n">${t[2]}</div></div>`).join('');

document.querySelector('#tbl tbody').innerHTML=D.map(r=>
 `<tr><td>${r.n}</td><td>${r.q}</td><td>${r.total.toLocaleString()}</td><td>${r.calls}</td><td>${r.ctx.toLocaleString()}</td><td>${r.out.toLocaleString()}</td><td>${r.sub_total?r.sub_total.toLocaleString():'—'}</td></tr>`).join('');

function nice(m){const p=Math.pow(10,Math.floor(Math.log10(m)));const r=m/p;
 return (r<=1?1:r<=2?2:r<=5?5:10)*p}
function axes(svg,max,lab){const g=[];const step=nice(max)/ (max>0?1:1);
 const top=nice(max*1.05),n=4;
 for(let i=0;i<=n;i++){const v=top*i/n,y=T+ih-ih*i/n;
  g.push(`<line class="gl" x1="${L}" y1="${y}" x2="${W-R}" y2="${y}"/><text class="ax" x="${L-8}" y="${y+3.5}" text-anchor="end">${fmt(Math.round(v))}</text>`)}
 D.forEach((d,i)=>{if(D.length<=20||i%Math.ceil(D.length/12)===0||i===D.length-1){
  const x=L+(D.length===1?iw/2:iw*i/(D.length-1));
  g.push(`<text class="ax" x="${x}" y="${H-9}" text-anchor="middle">${d.n}</text>`)}});
 svg.dataset.top=top;return g.join('')}

function hover(svg,key){
 const cross=`<line class="cross" id="${svg.id}cr" y1="${T}" y2="${T+ih}"/>`;
 svg.insertAdjacentHTML('beforeend',cross+`<rect class="hit" x="${L}" y="${T}" width="${iw}" height="${ih}"/>`);
 const cr=document.getElementById(svg.id+'cr');
 svg.addEventListener('mousemove',ev=>{const b=svg.getBoundingClientRect();
  const px=(ev.clientX-b.left)/b.width*W;
  let i=Math.round((px-L)/(D.length===1?iw:iw/(D.length-1)));i=Math.max(0,Math.min(D.length-1,i));
  const d=D[i],x=L+(D.length===1?iw/2:iw*i/(D.length-1));
  cr.setAttribute('x1',x);cr.setAttribute('x2',x);cr.style.opacity=.55;
  tip.innerHTML=`<b>第 ${d.n} 轮</b> · ${d[key].toLocaleString()} token<br>调用 ${d.calls} 次 · 输出 ${d.out.toLocaleString()}`+
   (d.sub_total?`<br>其中 subagent ${d.sub_total.toLocaleString()}`:'')+
   `<span class="q">${d.q.slice(0,90)}</span>`;
  tip.style.left=Math.min(ev.clientX+13,innerWidth-285)+'px';
  tip.style.top=(ev.clientY-14)+'px';tip.style.opacity=1});
 svg.addEventListener('mouseleave',()=>{tip.style.opacity=0;cr.style.opacity=0});
}

// 折线：单次上下文
(function(){const svg=document.getElementById('c2');
 const max=Math.max(...D.map(d=>d.ctx));svg.innerHTML=axes(svg,max);
 const top=+svg.dataset.top;
 const X=i=>L+(D.length===1?iw/2:iw*i/(D.length-1)),Y=v=>T+ih-ih*v/top;
 const pts=D.map((d,i)=>`${X(i)},${Y(d.ctx)}`).join(' ');
 svg.insertAdjacentHTML('beforeend',
  `<polyline points="${pts}" fill="none" stroke="var(--series-1)" stroke-width="2.2" stroke-linejoin="round"/>`+
  D.map((d,i)=>`<circle cx="${X(i)}" cy="${Y(d.ctx)}" r="2.6" fill="var(--series-1)"/>`).join(''));
 hover(svg,'ctx')})();

// 柱状：每轮总量
(function(){const svg=document.getElementById('c1');
 const max=Math.max(...D.map(d=>d.total));svg.innerHTML=axes(svg,max);
 const top=+svg.dataset.top;
 const bw=Math.max(4,iw/D.length*0.62);
 const X=i=>L+(D.length===1?iw/2:iw*i/(D.length-1)),Y=v=>T+ih-ih*v/top;
 svg.insertAdjacentHTML('beforeend',D.map((d,i)=>
  `<rect x="${X(i)-bw/2}" y="${Y(d.total)}" width="${bw}" height="${T+ih-Y(d.total)}" fill="var(--series-2)"/>`).join(''));
 const mi=D.findIndex(d=>d.total===max);
 svg.insertAdjacentHTML('beforeend',
  `<text class="dl" x="${X(mi)}" y="${Y(max)-6}" text-anchor="middle">${fmt(max)} · ${D[mi].calls} 次调用</text>`);
 hover(svg,'total')})();
</script></body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session", nargs="?", help="会话 id 前缀")
    ap.add_argument("-o", "--out", help="输出 HTML 路径")
    ap.add_argument("-p", "--project", help="项目 cwd（默认当前目录）")
    ap.add_argument("--list", action="store_true", help="列出该项目下的会话")
    ap.add_argument("--no-subagents", action="store_true")
    a = ap.parse_args()

    pdir = project_dir(a.project)
    files = sorted(glob.glob(os.path.join(pdir, "*.jsonl")))
    if not files:
        sys.exit(f"没有找到会话记录: {pdir}")

    if a.list or not a.session:
        for f in files:
            entries = load(f)
            prompts = [e for e in entries if is_real_prompt(e)]
            ts = [e.get("timestamp") for e in entries if e.get("timestamp")]
            first = (
                " ".join(text_of(prompts[0]["message"]).split())[:46] if prompts else "(空)"
            )
            print(
                f"{os.path.basename(f)[:8]}  轮次 {len(prompts):>3}  "
                f"{(ts[0] if ts else '?')[:19]} → {(ts[-1] if ts else '?')[11:19]}  {first}"
            )
        if a.list:
            return

    match = [f for f in files if os.path.basename(f).startswith(a.session)]
    if len(match) != 1:
        sys.exit(f"会话前缀 {a.session!r} 匹配到 {len(match)} 个文件")
    path = match[0]
    sid = os.path.basename(path)[: -len(".jsonl")]

    turns, orphan = analyze(path, include_subagents=not a.no_subagents)
    if not turns:
        sys.exit("这个会话里没有找到用户轮次")

    tot = sum(t["total"] for t in turns)
    print(f"\n会话 {sid}")
    print(f"轮次 {len(turns)} · 总量 {tot:,} · 调用 {sum(t['calls'] for t in turns)} · "
          f"输出 {sum(t['out'] for t in turns):,} · 峰值上下文 {max(t['ctx'] for t in turns):,}")
    sub = sum(t["sub_total"] for t in turns)
    if sub:
        print(f"其中 subagent {sub:,}（{sub / tot * 100:.1f}%）")
    if orphan:
        print(f"注意: {len(orphan)} 个 subagent 记录没能归到任何一轮（发起它的 tool_use 还没落盘）")
    print()
    for t in turns:
        print(f"  {t['n']:>3}  总 {t['total']:>12,}  调用 {t['calls']:>4}  "
              f"上下文 {t['ctx']:>9,}  输出 {t['out']:>8,}  {t['q'][:40]}")

    data = [
        {k: t[k] for k in ("n", "q", "total", "calls", "ctx", "out", "sub_total")}
        for t in turns
    ]
    for d in data:
        if len(d["q"]) > 44:
            d["q"] = d["q"][:44] + "…"

    sub_line = (
        f"会话 {sid[:8]} · {len(turns)} 个用户轮次 · 数据取自 Claude Code 会话记录的逐条 usage 字段"
        + (f" · 含 subagent 用量 {sub:,}" if sub else "")
    )
    html = (
        TEMPLATE_HEAD.replace("__SUB__", sub_line).replace(
            "__DATA__", json.dumps(data, ensure_ascii=False)
        )
        + TEMPLATE_TAIL
    )
    default_dir = os.path.join("QATests", "Run", "Reports")
    if a.out is None:
        os.makedirs(default_dir, exist_ok=True)
    out = a.out or os.path.join(default_dir, f"token-usage-{sid[:8]}.html")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(html)
    print(f"\n已写入 {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
