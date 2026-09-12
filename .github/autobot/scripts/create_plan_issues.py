#!/usr/bin/env python3
"""Create task issues from plan output with idempotency protection."""

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass


class PlanIssueError(RuntimeError):
    pass


def run(command: list[str]) -> str:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise PlanIssueError(f"{' '.join(command)} failed: {detail}")
    return result.stdout


def run_json(command: list[str]) -> object:
    return json.loads(run(command))


@dataclass
class TaskSpec:
    title: str
    body: str
    depends_on_titles: list[str]


def validate_tasks(payload: dict) -> list[TaskSpec]:
    tasks_raw = payload.get("tasks")
    if not isinstance(tasks_raw, list) or not tasks_raw:
        raise PlanIssueError("plan output must include a non-empty tasks array")

    tasks: list[TaskSpec] = []
    for raw in tasks_raw:
        if not isinstance(raw, dict):
            raise PlanIssueError("each task entry must be an object")
        title = str(raw.get("title", "")).strip()
        body = str(raw.get("body", "")).strip()
        deps_raw = raw.get("depends_on_titles", [])
        if not title or not body:
            raise PlanIssueError("each task must include non-empty title and body")
        if not isinstance(deps_raw, list) or any(not isinstance(dep, str) for dep in deps_raw):
            raise PlanIssueError("depends_on_titles must be a list of strings")
        tasks.append(TaskSpec(title=title, body=body, depends_on_titles=[dep.strip() for dep in deps_raw if dep.strip()]))
    return tasks


def parse_issue_number(issue_url: str) -> int:
    try:
        return int(issue_url.rstrip("/").split("/")[-1])
    except ValueError as exc:
        raise PlanIssueError(f"could not parse issue number from URL: {issue_url}") from exc


def create_issue(repo: str, title: str, body: str) -> tuple[int, str]:
    url = run(["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body, "--label", "autobot-task"]).strip()
    number = parse_issue_number(url)
    return number, url


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--feature-issue", required=True, type=int)
    parser.add_argument("--plan-json", required=True)
    args = parser.parse_args()

    payload = json.loads(open(args.plan_json, "r", encoding="utf-8").read())
    status = str(payload.get("status", "")).strip().lower()
    if status != "completed":
        raise PlanIssueError("plan output status is not completed")
    feature_comment = str(payload.get("feature_comment", "")).strip()
    tasks = validate_tasks(payload)

    existing = run_json([
        "gh", "issue", "list",
        "--repo", args.repo,
        "--state", "open",
        "--label", "autobot-task",
        "--search", f"\"Autobot Parent: #{args.feature_issue}\"",
        "--json", "number,title,url",
    ])
    if isinstance(existing, list) and existing:
        existing_sorted = sorted(existing, key=lambda item: int(item.get("number", 0)))
        lines = ["Autobot plan already exists. Reusing existing task issues:"]
        for item in existing_sorted:
            lines.append(f"- #{item['number']} {item['title']}")
        lines.append("")
        lines.append(f"Parent feature: #{args.feature_issue}")
        print(json.dumps({
            "created": False,
            "tasks": existing_sorted,
            "feature_comment": "\n".join(lines),
        }))
        return 0

    created: list[dict] = []
    title_to_number: dict[str, int] = {}

    for task in tasks:
        metadata = (
            f"\n\n---\n"
            f"Autobot Parent: #{args.feature_issue}\n"
            f"Autobot Task: true\n"
            f"Autobot Depends on titles: {', '.join(task.depends_on_titles) if task.depends_on_titles else 'None'}\n"
        )
        issue_number, issue_url = create_issue(args.repo, task.title, task.body + metadata)
        created.append({
            "number": issue_number,
            "title": task.title,
            "url": issue_url,
            "depends_on_titles": task.depends_on_titles,
        })
        title_to_number[task.title] = issue_number

    for item in created:
        deps = [title_to_number[title] for title in item["depends_on_titles"] if title in title_to_number]
        if deps:
            dep_refs = ", ".join(f"#{value}" for value in deps)
            run([
                "gh", "issue", "comment", str(item["number"]),
                "--repo", args.repo,
                "--body", f"Dependency note: Depends on {dep_refs}.",
            ])

    comment_lines = [feature_comment] if feature_comment else []
    comment_lines.append("Created implementation task issues:")
    for item in created:
        deps = [title_to_number[title] for title in item["depends_on_titles"] if title in title_to_number]
        dep_suffix = f" (depends on {', '.join(f'#{dep}' for dep in deps)})" if deps else ""
        comment_lines.append(f"- #{item['number']} {item['title']}{dep_suffix}")

    print(json.dumps({
        "created": True,
        "tasks": created,
        "feature_comment": "\n".join(comment_lines),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

