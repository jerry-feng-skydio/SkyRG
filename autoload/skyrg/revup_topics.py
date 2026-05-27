#!/usr/bin/env python3
"""
Parse revup topics from the current git branch and output a JSON tree.

Usage: python3 revup_topics.py [base_branch]

If base_branch is not given, attempts to auto-detect using revup's logic,
falling back to origin/main or origin/master.

Output JSON:
{
  "topics": [
    {"name": "foo", "relative": null, "commits": 2, "title": "First commit title"},
    {"name": "foo2", "relative": "foo", "commits": 1, "title": "Second commit title"}
  ],
  "base_branch": "origin/main",
  "error": null
}
"""

import configparser
import json
import os
import re
import subprocess
import sys

RE_TAGS = re.compile(r"^(?P<tagname>[a-zA-Z\-]+):(?P<tagvalue>.*)$", re.MULTILINE)
COMMIT_SEP = "---COMMIT_SEP---"

CONFIG_FILE_NAME = ".revupconfig"
USER_CONFIG_PATH = os.path.join(os.path.expanduser("~"), CONFIG_FILE_NAME)


def run_git(*args):
    """Run a git command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            ["git"] + list(args),
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def read_revup_config():
    """Read .revupconfig from repo root and user home."""
    conf = configparser.ConfigParser()
    repo_root = run_git("rev-parse", "--show-toplevel")
    if repo_root:
        repo_config = os.path.join(repo_root, CONFIG_FILE_NAME)
        if os.path.isfile(repo_config):
            conf.read(repo_config)
    if os.path.isfile(USER_CONFIG_PATH):
        conf.read(USER_CONFIG_PATH)
    return conf


def detect_base_branch():
    """Detect the base branch using revup's config and git fork-point logic."""
    conf = read_revup_config()

    remote_name = conf.get("revup", "remote_name", fallback="origin")
    main_branch = conf.get("revup", "main_branch", fallback="main")
    base_branch_globs = conf.get("revup", "base_branch_globs", fallback="")

    # Verify main branch exists on remote, try master fallback
    main_ref = f"{remote_name}/{main_branch}"
    if run_git("rev-parse", "--verify", main_ref) is None:
        for fallback in ["master", "main"]:
            if fallback != main_branch:
                test_ref = f"{remote_name}/{fallback}"
                if run_git("rev-parse", "--verify", test_ref) is not None:
                    main_branch = fallback
                    main_ref = test_ref
                    break

    # Parse base branch globs into list
    globs = [g.strip() for g in base_branch_globs.strip().splitlines() if g.strip()]

    if not globs:
        # No globs configured, just use main branch
        return main_ref

    # Collect candidate branches: main + glob matches
    # Use git for-each-ref to find branches matching the globs
    ref_args = ["--format", "%(refname:short)"]
    ref_args.append(f"refs/remotes/{remote_name}/{main_branch}")
    for g in globs:
        ref_args.append(f"refs/remotes/{remote_name}/{g}")

    # Filter to branches that contain the fork-point with main
    fork_with_main = run_git("merge-base", "HEAD", main_ref)
    if fork_with_main:
        ref_args.extend(["--contains", fork_with_main])

    raw = run_git("for-each-ref", *ref_args)
    if not raw:
        return main_ref

    candidates = [b.strip() for b in raw.splitlines() if b.strip()]
    if not candidates:
        return main_ref
    if len(candidates) == 1:
        return candidates[0]

    # Pick the candidate with the shortest distance (most recent fork-point)
    best = None
    best_dist = None
    for branch in candidates:
        dist_str = run_git("rev-list", "--count", "--first-parent",
                           f"{branch}..HEAD")
        if dist_str is None:
            continue
        dist = int(dist_str)
        if best_dist is None or dist < best_dist:
            best_dist = dist
            best = branch

    return best if best else main_ref


def get_merge_base(base_branch):
    """Get the merge-base between HEAD and base_branch."""
    return run_git("merge-base", "HEAD", base_branch)


def get_commits(merge_base):
    """Get commit hashes and messages from merge_base..HEAD."""
    fmt = "%H" + COMMIT_SEP + "%B" + COMMIT_SEP + COMMIT_SEP
    raw = run_git("log", "--reverse", "--format=" + fmt, merge_base + "..HEAD")
    if not raw:
        return []

    commits = []
    for block in raw.split(COMMIT_SEP + COMMIT_SEP):
        block = block.strip()
        if not block:
            continue
        parts = block.split(COMMIT_SEP, 1)
        if len(parts) != 2:
            continue
        commit_hash = parts[0].strip()
        commit_msg = parts[1].strip()
        commits.append((commit_hash, commit_msg))
    return commits


def parse_tags(commit_msg):
    """Parse revup tags from a commit message. Returns dict of tag -> set of values."""
    tags = {}
    for m in RE_TAGS.finditer(commit_msg):
        tagname = m.group("tagname").lower().strip()
        values = {v.strip() for v in m.group("tagvalue").split(",") if v.strip()}
        if tagname in tags:
            tags[tagname].update(values)
        else:
            tags[tagname] = values
    return tags


def get_title(commit_msg):
    """Extract the first line of a commit message as the title."""
    return commit_msg.split("\n", 1)[0].strip()


def main():
    base_branch = sys.argv[1] if len(sys.argv) > 1 else None

    if not base_branch:
        base_branch = detect_base_branch()
    if not base_branch:
        print(json.dumps({
            "topics": [], "base_branch": None,
            "error": "Could not detect base branch"
        }))
        return

    merge_base = get_merge_base(base_branch)
    if not merge_base:
        print(json.dumps({
            "topics": [], "base_branch": base_branch,
            "error": "Could not find merge-base with " + base_branch
        }))
        return

    commits = get_commits(merge_base)

    # Parse topics from commits
    # topic_name -> {relative, commits, title}
    topic_order = []
    topic_data = {}

    for commit_hash, commit_msg in commits:
        tags = parse_tags(commit_msg)
        topic_names = tags.get("topic", set())
        if not topic_names:
            continue

        name = min(topic_names)  # revup uses min() for single-value tags
        relative = None
        rel_tags = tags.get("relative", set())
        if rel_tags:
            relative = min(rel_tags)

        if name not in topic_data:
            topic_order.append(name)
            topic_data[name] = {
                "name": name,
                "relative": relative,
                "commits": 1,
                "title": get_title(commit_msg),
            }
        else:
            topic_data[name]["commits"] += 1
            # If any commit in the topic specifies a relative, use it
            if relative and topic_data[name]["relative"] is None:
                topic_data[name]["relative"] = relative

    # Build ordered list preserving commit order
    topics = [topic_data[name] for name in topic_order]

    print(json.dumps({
        "topics": topics,
        "base_branch": base_branch,
        "error": None,
    }))


if __name__ == "__main__":
    main()
