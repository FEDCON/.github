#!/usr/bin/env python3
"""retired-paths-ci.py: does this change ADD a retired path?  Read-only. Ledger row 1.8.

    retired-paths-ci.py <base-ref>          # e.g. origin/main; compares <base-ref>...HEAD

The CI half of plan section 5, layer 5. It checks only the lines a pull request ADDS, in code files, against
the same patterns oldpaths-sweep.sh uses for whole default branches (imported from that file, so the two
cannot drift): SimpleMDM write calls, attribute PUTs, script-job POSTs, SSH change commands, ~/credentials,
mcp-secrets.json, the owner key file, gcs-sa.json, `{{...key...}}` in fleet scripts, committed private keys.
Documentation is skipped: a doc that says "never read ~/credentials" is teaching the rule, not breaking it.

Prints pattern and file names only, never the matched text. Exit 0 = nothing added, 1 = something added.
Runs as an enterprise ruleset's required workflow in EVALUATE mode first (rule insights record what it would
have blocked, nobody is stopped), then active once a week of insights shows no false positives.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SWEEP = os.path.join(HERE, "oldpaths-sweep.sh")
DOC = re.compile(r"\.(md|txt|html?|rst|adoc|ipynb|csv|tsv|jsonl)$", re.I)
# Files whose job is to NAME the retired paths: the guards, their tests, and these checks.
SELF = re.compile(r"(^|/)(retired-paths[^/]*|oldpaths-sweep\.sh|retired-paths-ci\.py)$|"
                  r"(^|/)systems/one-touch/verify/|(^|/)components/hook-audit/tests/|"
                  r"(^|/)components/managed-settings/server-managed|(^|/)components/hook-registry\.json$")


def patterns():
    """The (name, [regexes], pathglobs) list, read out of oldpaths-sweep.sh's P = [...] block."""
    src = open(SWEEP).read()
    block = src[src.index("P = ["):src.index("]\nDOC = ")] + "]"
    ns = {}
    exec(block, {"re": re}, ns)
    return ns["P"]


def added_lines(base):
    diff = subprocess.run(["git", "diff", "--unified=0", "--no-color", f"{base}...HEAD"],
                          capture_output=True, text=True, check=True).stdout
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("+") and not line.startswith("+++") and path:
            yield path, line[1:]


def glob_ok(path, globs):
    if not globs:
        return True
    import fnmatch
    return any(fnmatch.fnmatch(os.path.basename(path), g) for g in globs)


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2].strip())
        return 2
    pats = [(n, [re.compile(r) for r in rx], g) for n, rx, g in patterns()]
    hits = {}
    for path, text in added_lines(sys.argv[1]):
        if DOC.search(path) or SELF.search(path):
            continue
        for name, rxs, globs in pats:
            if glob_ok(path, globs) and all(r.search(text) for r in rxs):
                hits.setdefault(name, set()).add(path)
    for name, files in sorted(hits.items()):
        print(f"ADDED  {name:16s} {len(files)} file(s): {', '.join(sorted(files))}")
    if hits:
        print("VERDICT FAIL retired paths: this change adds " + ", ".join(sorted(hits)) +
              ". Replacements: keys from Secret Manager at run time (FEDCON Keys on Macs); per-person values"
              " from Google's FEDCON fields; SimpleMDM changes are Brad's clicks; a Mac change is a Munki item.")
        return 1
    print("VERDICT PASS retired paths: nothing retired added")
    return 0


if __name__ == "__main__":
    sys.exit(main())
