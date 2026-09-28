#!/usr/bin/env bash
# oldpaths-sweep.sh: do retired paths still live on any FEDCON default branch?  Read-only.
#
# git grep over each repo's origin default branch (after a quiet fetch; no GitHub REST calls) for
# the retired-path patterns of the one-touch plan (section 5). Prints matching-line counts per repo
# and pattern, split code/docs, never the matched text. Exit 0 = nothing found, 1 = anything found.
#
# Repos: ~/.claude-config, ~/admin-test (if a git repo), and every git repo under ~/projects
# (not ~/projects/_wt) whose origin is github.com/FEDCON/*, each remote swept once.
# Env: NO_FETCH=1 skips the fetch; ROOTS overrides the repo list (space-separated paths);
#      SHOW_FILES=1 also prints file paths (names only) per pattern.
# This folder (systems/one-touch/verify/) names every pattern, so it is excluded from the sweep.
set -uo pipefail

python3 - <<'PY'
import os, re, subprocess, sys
from collections import defaultdict

HOME = os.path.expanduser("~")
fetch = os.environ.get("NO_FETCH") != "1"
show_files = os.environ.get("SHOW_FILES") == "1"

# (name, list of -e patterns joined with --and, pathspecs or None)
P = [
  ("smdm-nonget",   [r"a\.simplemdm\.com", r"(-X ?['\"]?(POST|PUT|PATCH|DELETE)|--request ?(POST|PUT|PATCH|DELETE)|method['\"]?[=:] ?['\"](POST|PUT|PATCH|DELETE)|requests\.(post|put|patch|delete)\()"], None),
  ("attr-put",      [r"custom_attribute", r"(-X ?['\"]?PUT|--request ?PUT|method['\"]?[=:] ?['\"]PUT|requests\.put\(|\.put\()"], None),
  ("script-jobs",   [r"script_jobs", r"(-X ?['\"]?POST|--request ?POST|method['\"]?[=:] ?['\"]POST|requests\.post\(|\.post\()"], None),
  ("ssh-change",    [r"ssh .*fedadmin", r"(sudo|\brm |\bkill\b|launchctl (load|unload|bootstrap|bootout|kickstart)|defaults write|chmod|chown|\bmv |\bcp |\btee\b|installer |softwareupdate|profiles (install|remove)|dscl .*-(create|delete|passwd))"], None),
  ("~/credentials", [r"(~|\$HOME|\$\{HOME\}|/Users/[A-Za-z0-9_.-]+)/credentials/"], None),
  ("mcp-secrets",   [r"mcp-secrets\.json"], None),
  ("owner-keyfile", [r"claude-workspace-admin\.json"], None),
  ("gcs-sa.json",   [r"gcs-sa\.json"], None),
  ("{{key}}-script",[r"\{\{[A-Za-z0-9_]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z0-9_]*\}\}"],
                    ["*.sh", "*.zsh", "*.bash", "*.py", "*.pkginfo", "*.plist", "*.mobileconfig", "*.command"]),
  ("private-key",   [r"-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|\"private_key\": ?\"-----BEGIN"], None),
]
DOC = re.compile(r"\.(md|txt|html?|rst|adoc|ipynb|csv|tsv|jsonl)$", re.I)
EXCL = [":(exclude)systems/one-touch/verify/*"]

def sh(args, cwd, timeout=120):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)

def origin(path):
    r = sh(["git", "remote", "get-url", "origin"], path)
    return r.stdout.strip() if r.returncode == 0 else ""

def slug(url):
    # github.com URLs and SSH host aliases (git@github-fedcon-config:FEDCON/claude-config.git)
    m = re.search(r"(?:github\.com[:/]+|^[^@\s]+@[^:\s]+:)([^/]+)/([^/]+?)(\.git)?/?$", url)
    return (m.group(1), m.group(2)) if m else (None, None)

roots = os.environ.get("ROOTS")
if roots:
    cands = roots.split()
else:
    cands = [f"{HOME}/.claude-config", f"{HOME}/admin-test"]
    pj = f"{HOME}/projects"
    for d in sorted(os.listdir(pj)):
        p = os.path.join(pj, d)
        if d == "_wt" or not os.path.isdir(p) or not os.path.exists(os.path.join(p, ".git")):
            continue
        cands.append(p)

seen, repos, skipped = set(), [], []
for p in cands:
    if not os.path.exists(os.path.join(p, ".git")):
        skipped.append((os.path.basename(p), "not a git repo")); continue
    owner, name = slug(origin(p))
    if not owner or owner.lower() != "fedcon":
        skipped.append((os.path.basename(p), "origin not FEDCON")); continue
    if name.lower() in seen:
        continue
    seen.add(name.lower()); repos.append((name, p))

def default_ref(p):
    if fetch:
        try: sh(["git", "fetch", "-q", "origin"], p, timeout=90)
        except subprocess.TimeoutExpired: pass
    r = sh(["git", "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"], p)
    if r.returncode == 0 and r.stdout.strip(): return r.stdout.strip()
    for b in ("origin/main", "origin/master"):
        if sh(["git", "rev-parse", "-q", "--verify", b], p).returncode == 0: return b
    return None

totals = defaultdict(lambda: [0, 0]); rows = []; unread = []
for name, p in repos:
    ref = default_ref(p)
    if not ref:
        unread.append((name, "no origin default branch")); continue
    for pname, pats, spec in P:
        args = ["git", "grep", "-I", "-c", "-E"]
        for i, pat in enumerate(pats):
            if i: args.append("--and")
            args += ["-e", pat]
        args += [ref, "--"] + (spec or ["."]) + EXCL
        r = sh(args, p)
        if r.returncode not in (0, 1):
            unread.append((name, f"{pname}: git grep rc {r.returncode}")); continue
        code = docs = 0; files = []
        for line in r.stdout.splitlines():
            # format: <ref>:<path>:<count>
            path_count = line[len(ref) + 1:]
            path, _, cnt = path_count.rpartition(":")
            n = int(cnt) if cnt.isdigit() else 0
            if DOC.search(path): docs += n
            else: code += n
            files.append(path)
        if code or docs:
            rows.append((name, pname, code, docs, files))
            totals[pname][0] += code; totals[pname][1] += docs

print(f"swept {len(repos)} FEDCON repos (default branch, fetched={'yes' if fetch else 'no'}); "
      f"{len(skipped)} dirs skipped (not git / not FEDCON)")
print(f"{'repo':38} {'pattern':16} {'code':>5} {'docs':>5}")
for name, pname, code, docs, files in sorted(rows):
    print(f"{name[:38]:38} {pname:16} {code:5d} {docs:5d}")
    if show_files:
        for f in files[:50]: print(f"    {f}")
print("--- totals per pattern (matching lines): code / docs / repos")
hit_repos = defaultdict(set)
for name, pname, *_ in rows: hit_repos[pname].add(name)
for pname, *_ in P:
    c, d = totals[pname]
    print(f"  {pname:16} {c:6d} {d:6d} {len(hit_repos[pname]):4d}")
for name, why in unread:
    print(f"UNREAD {name}: {why}")
tc = sum(v[0] for v in totals.values()); td = sum(v[1] for v in totals.values())
repos_hit = len({r[0] for r in rows})
if tc or td:
    print(f"VERDICT FAIL old paths: {tc} code + {td} doc lines in {repos_hit} repos")
    sys.exit(1)
print("VERDICT PASS old paths: none found on any swept default branch")
PY
