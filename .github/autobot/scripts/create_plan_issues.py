#!/usr/bin/env python3
"""Create and maintain main feature + task issues from plan output."""

from __future__ import annotations

import argparse
import json
import re
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


def run_result(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False)


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
    seen_titles: set[str] = set()
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
        if title in seen_titles:
            raise PlanIssueError(f"task titles must be unique, duplicate title: {title}")
        seen_titles.add(title)
        tasks.append(
            TaskSpec(
                title=title,
                body=body,
                depends_on_titles=[dep.strip() for dep in deps_raw if dep.strip()],
            )
        )
    return tasks


def parse_issue_number(issue_url: str) -> int:
    try:
        return int(issue_url.rstrip("/").split("/")[-1])
    except ValueError as exc:
        raise PlanIssueError(f"could not parse issue number from URL: {issue_url}") from exc


def sync_project_stage(
    owner: str | None,
    number: str | None,
    status_field: str,
    issue_url: str,
    stage: str,
) -> str | None:
    if not owner or not number:
        return None

    add_result = run_result(
        [
            "gh",
            "project",
            "item-add",
            number,
            "--owner",
            owner,
            "--url",
            issue_url,
            "--format",
            "json",
        ]
    )
    if add_result.returncode != 0:
        combined = f"{add_result.stdout}\n{add_result.stderr}".lower()
        if not re.search(r"already (exists|added)|item .* already", combined):
            if "could not resolve to a projectv2" in combined:
                return (
                    f"failed to add {issue_url} to project {owner}#{number}: "
                    "GraphQL could not resolve ProjectV2. Verify AUTOBOT_PROJECT_OWNER/AUTOBOT_PROJECT_NUMBER, "
                    "and ensure AUTOBOT_PROJECT_TOKEN has org ProjectV2 write access (and SSO authorization when required)."
                )
            return f"failed to add {issue_url} to project {owner}#{number}: {(add_result.stderr or add_result.stdout).strip()}"

    edit_result = run_result(
        [
            "gh",
            "project",
            "item-edit",
            number,
            "--owner",
            owner,
            "--url",
            issue_url,
            "--field",
            status_field,
            "--value",
            stage,
            "--format",
            "json",
        ]
    )
    if edit_result.returncode != 0:
        combined = f"{edit_result.stdout}\n{edit_result.stderr}".lower()
        if "could not resolve to a projectv2" in combined:
            return (
                f"failed to set project stage '{stage}' for {issue_url}: "
                "GraphQL could not resolve ProjectV2. Verify AUTOBOT_PROJECT_OWNER/AUTOBOT_PROJECT_NUMBER, "
                "and ensure AUTOBOT_PROJECT_TOKEN has org ProjectV2 write access (and SSO authorization when required)."
            )
        return f"failed to set project stage '{stage}' for {issue_url}: {(edit_result.stderr or edit_result.stdout).strip()}"
    return None


def short_summary(markdown_text: str) -> str:
    text = markdown_text.strip()
    if not text:
        return "Implementation tasks generated from the approved design."
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    if not paragraphs:
        return "Implementation tasks generated from the approved design."
    first = re.sub(r"\s+", " ", paragraphs[0]).strip()
    if len(first) > 600:
        first = first[:597].rstrip() + "..."
    return first


def existing_main_feature(repo: str, source_issue: int) -> dict | None:
    matches = run_json(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "all",
            "--search",
            f"\"Autobot Main Parent: #{source_issue}\"",
            "--json",
            "number,title,url,state,body",
        ]
    )
    if not isinstance(matches, list):
        return None
    valid = [
        item
        for item in matches
        if isinstance(item, dict)
        and f"Autobot Main Parent: #{source_issue}" in str(item.get("body", ""))
        and "Autobot Main Feature: true" in str(item.get("body", ""))
    ]
    if not valid:
        return None
    valid.sort(key=lambda item: int(item.get("number", 0)), reverse=True)
    return valid[0]


def create_main_feature_issue(
    repo: str,
    source_issue: int,
    source_title: str,
    summary: str,
    design_url: str | None,
) -> tuple[int, str]:
    title = f"Feature: {source_title}".strip()
    design_line = f"- Full design: {design_url}" if design_url else "- Full design: N/A"
    body = (
        "## Design summary\n"
        f"{summary}\n\n"
        "## Source context\n"
        f"- Original approved specification issue: #{source_issue}\n"
        f"{design_line}\n\n"
        "## Implementation tasks\n"
        "- Tasks will be linked below by Autobot planning.\n\n"
        "---\n"
        f"Autobot Main Parent: #{source_issue}\n"
        "Autobot Main Feature: true\n"
    )
    url = run(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title,
            "--body",
            body,
        ]
    ).strip()
    return parse_issue_number(url), url


def create_task_issue(repo: str, title: str, body: str) -> tuple[int, str]:
    primary = run_result(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title,
            "--body",
            body,
            "--label",
            "autobot-task",
            "--label",
            "autoboot",
        ]
    )
    if primary.returncode == 0:
        issue_url = primary.stdout.strip()
        return parse_issue_number(issue_url), issue_url
    fallback = run_result(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title,
            "--body",
            body,
            "--label",
            "autobot-task",
        ]
    )
    if fallback.returncode != 0:
        detail = (fallback.stderr or fallback.stdout or primary.stderr or primary.stdout).strip()
        raise PlanIssueError(f"failed to create task issue '{title}': {detail}")
    issue_url = fallback.stdout.strip()
    return parse_issue_number(issue_url), issue_url


def existing_tasks_for_main(repo: str, main_feature_issue: int) -> list[dict]:
    existing = run_json(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            repo,
            "--state",
            "open",
            "--label",
            "autobot-task",
            "--search",
            f"\"Autobot Main Feature: #{main_feature_issue}\"",
            "--json",
            "number,title,url,body",
        ]
    )
    if not isinstance(existing, list):
        return []
    valid: list[dict] = []
    for item in existing:
        if not isinstance(item, dict):
            continue
        body = str(item.get("body", ""))
        if f"Autobot Main Feature: #{main_feature_issue}" not in body:
            continue
        valid.append(item)
    valid.sort(key=lambda item: int(item.get("number", 0)))
    return valid


def update_main_feature_body(
    repo: str,
    main_feature_issue: int,
    source_issue: int,
    summary: str,
    design_url: str | None,
    tasks: list[dict],
) -> None:
    task_lines = [f"- [ ] #{item['number']} {item['title']}" for item in tasks]
    if not task_lines:
        task_lines = ["- No tasks were created."]
    design_line = f"- Full design: {design_url}" if design_url else "- Full design: N/A"
    body = (
        "## Design summary\n"
        f"{summary}\n\n"
        "## Source context\n"
        f"- Original approved specification issue: #{source_issue}\n"
        f"{design_line}\n\n"
        "## Implementation tasks\n"
        + "\n".join(task_lines)
        + "\n\n---\n"
        f"Autobot Main Parent: #{source_issue}\n"
        "Autobot Main Feature: true\n"
    )
    run(
        [
            "gh",
            "issue",
            "edit",
            str(main_feature_issue),
            "--repo",
            repo,
            "--body",
            body,
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--feature-issue", required=True, type=int)
    parser.add_argument("--plan-json", required=True)
    parser.add_argument("--default-branch", required=True)
    parser.add_argument("--design-path", required=True)
    parser.add_argument("--project-owner")
    parser.add_argument("--project-number")
    parser.add_argument("--project-status-field", default="Status")
    args = parser.parse_args()

    payload = json.loads(open(args.plan_json, "r", encoding="utf-8").read())
    status = str(payload.get("status", "")).strip().lower()
    if status != "completed":
        raise PlanIssueError("plan output status is not completed")

    feature_comment = str(payload.get("feature_comment", "")).strip()
    tasks = validate_tasks(payload)
    warnings: list[str] = []

    source_issue_data = run_json(["gh", "api", f"repos/{args.repo}/issues/{args.feature_issue}"])
    if not isinstance(source_issue_data, dict):
        raise PlanIssueError("feature issue lookup failed")
    source_title = str(source_issue_data.get("title", f"#{args.feature_issue}"))
    source_url = str(source_issue_data.get("html_url", f"https://github.com/{args.repo}/issues/{args.feature_issue}"))
    summary = short_summary(str(payload.get("main_feature_summary", "")) or feature_comment)
    design_url = (
        f"https://github.com/{args.repo}/blob/{args.default_branch}/{args.design_path}"
        if args.design_path
        else None
    )

    main_feature = existing_main_feature(args.repo, args.feature_issue)
    main_created = False
    if main_feature:
        main_number = int(main_feature["number"])
        main_url = str(main_feature["url"])
    else:
        main_number, main_url = create_main_feature_issue(
            repo=args.repo,
            source_issue=args.feature_issue,
            source_title=source_title,
            summary=summary,
            design_url=design_url,
        )
        main_created = True

    warning = sync_project_stage(
        owner=args.project_owner,
        number=args.project_number,
        status_field=args.project_status_field,
        issue_url=main_url,
        stage="Ready to implement",
    )
    if warning:
        warnings.append(warning)

    existing_tasks = existing_tasks_for_main(args.repo, main_number)
    existing_by_title = {str(item.get("title", "")): item for item in existing_tasks}
    created: list[dict] = []
    title_to_number: dict[str, int] = {}
    tasks_for_body: list[dict] = []
    for task in tasks:
        existing = existing_by_title.get(task.title)
        if existing:
            issue_number = int(existing["number"])
            issue_url = str(existing["url"])
            payload_item = {
                "number": issue_number,
                "title": task.title,
                "url": issue_url,
                "depends_on_titles": task.depends_on_titles,
            }
        else:
            metadata = (
                f"\n\n---\n"
                f"Autobot Main Feature: #{main_number}\n"
                f"Autobot Source Feature: #{args.feature_issue}\n"
                f"Autobot Task: true\n"
                f"Autobot Depends on titles: {', '.join(task.depends_on_titles) if task.depends_on_titles else 'None'}\n"
            )
            issue_number, issue_url = create_task_issue(args.repo, task.title, task.body + metadata)
            payload_item = {
                "number": issue_number,
                "title": task.title,
                "url": issue_url,
                "depends_on_titles": task.depends_on_titles,
            }
            created.append(payload_item)
        tasks_for_body.append(payload_item)
        title_to_number[task.title] = issue_number
        warning = sync_project_stage(
            owner=args.project_owner,
            number=args.project_number,
            status_field=args.project_status_field,
            issue_url=issue_url,
            stage="Ready to implement",
        )
        if warning:
            warnings.append(warning)

    for item in created:
        deps = [title_to_number[title] for title in item["depends_on_titles"] if title in title_to_number]
        if deps:
            dep_refs = ", ".join(f"#{value}" for value in deps)
            run(
                [
                    "gh",
                    "issue",
                    "comment",
                    str(item["number"]),
                    "--repo",
                    args.repo,
                    "--body",
                    f"Dependency note: Depends on {dep_refs}.",
                ]
            )

    update_main_feature_body(
        repo=args.repo,
        main_feature_issue=main_number,
        source_issue=args.feature_issue,
        summary=summary,
        design_url=design_url,
        tasks=tasks_for_body,
    )

    lines = []
    if feature_comment:
        lines.append(feature_comment)
        lines.append("")
    if main_created:
        lines.append(f"Created main feature issue: #{main_number}")
    else:
        lines.append(f"Reused main feature issue: #{main_number}")
    lines.append(f"Main feature URL: {main_url}")
    lines.append("")
    lines.append("Implementation tasks:")
    for item in sorted(tasks_for_body, key=lambda value: int(value["number"])):
        deps = [title_to_number[title] for title in item.get("depends_on_titles", []) if title in title_to_number]
        dep_suffix = f" (depends on {', '.join(f'#{dep}' for dep in deps)})" if deps else ""
        lines.append(f"- #{item['number']} {item['title']}{dep_suffix}")
    lines.append("")
    lines.append(f"Source specification issue: #{args.feature_issue}")

    if warnings:
        lines.append("")
        lines.append("Project sync warnings:")
        lines.extend(f"- {warning}" for warning in warnings)

    close_comment = (
        f"Planning is complete and this specification issue is now superseded by main feature #{main_number}.\n\n"
        f"Main feature: {main_url}\n"
        f"Original specification issue: {source_url}"
    )

    print(
        json.dumps(
            {
                "created": bool(created),
                "main_feature": {
                    "number": main_number,
                    "url": main_url,
                    "created": main_created,
                },
                "tasks": sorted(tasks_for_body, key=lambda value: int(value["number"])),
                "feature_comment": "\n".join(lines),
                "close_comment": close_comment,
                "warnings": warnings,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
