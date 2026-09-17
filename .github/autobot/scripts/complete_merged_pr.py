#!/usr/bin/env python3
"""Complete an Autobot task after its implementation PR is merged."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

from create_plan_issues import PlanIssueError, run, run_json, sync_project_stage


PHASE_LABELS = {
    "autobot-ready-for-spec",
    "autobot-creating-specification",
    "autobot-review-specification",
    "autobot-ready-to-implement",
    "autobot-implementing",
    "autobot-in-review",
    "autobot-blocked",
}


def complete_pr(
    repository: str,
    pr_number: int,
    default_branch: str,
    project_owner: str = "",
    project_number: str = "",
    project_status_field: str = "Status",
) -> bool:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise PlanIssueError("repository must be in owner/repo form")
    if pr_number < 1 or not default_branch:
        raise PlanIssueError("a positive PR number and default branch are required")
    if bool(project_owner) != bool(project_number):
        raise PlanIssueError("configure both AUTOBOT_PROJECT_OWNER and AUTOBOT_PROJECT_NUMBER")
    if project_number and not re.fullmatch(r"[1-9][0-9]*", project_number):
        raise PlanIssueError("AUTOBOT_PROJECT_NUMBER must be a positive integer")

    pr = run_json(["gh", "api", f"repos/{repository}/pulls/{pr_number}"])
    if pr["merged"] is not True or pr["state"] != "closed":
        print(f"skip: PR #{pr_number} has not been merged")
        return False
    if pr["base"]["ref"] != default_branch:
        print(f"skip: PR #{pr_number} was not merged into the default branch")
        return False
    head_repo = pr["head"]["repo"]
    if not head_repo or head_repo["full_name"].lower() != repository.lower():
        print(f"skip: PR #{pr_number} is not from this repository")
        return False
    branch_match = re.fullmatch(r"autobot/([1-9][0-9]*)-[a-z0-9-]+", pr["head"]["ref"])
    if not branch_match:
        print(f"skip: PR #{pr_number} does not use an Autobot implementation branch")
        return False

    # Both providers own one deterministic implementation branch per task.
    issue_number = branch_match.group(1)
    issue_endpoint = f"repos/{repository}/issues/{issue_number}"
    issue = run_json(["gh", "api", issue_endpoint])
    labels = {label["name"] for label in issue["labels"]}
    if "pull_request" in issue or "autobot-task" not in labels:
        print(f"skip: #{issue_number} is not an Autobot task issue")
        return False
    if not labels.intersection({"autobot-in-review", "autobot-done"}):
        print(f"skip: task #{issue_number} is not in review or already done")
        return False

    if "autobot-done" not in labels:
        run([
            "gh", "label", "create", "autobot-done", "--repo", repository,
            "--color", "0E8A16", "--description",
            "Implementation PR merged; task completed", "--force",
        ])
    stale_labels = sorted(labels.intersection(PHASE_LABELS))
    if "autobot-done" not in labels or stale_labels:
        command = ["gh", "issue", "edit", issue_number, "--repo", repository]
        for label in stale_labels:
            command.extend(["--remove-label", label])
        command.extend(["--add-label", "autobot-done"])
        run(command)

    if issue["state"] != "closed" or issue.get("state_reason") != "completed":
        run([
            "gh", "api", "--method", "PATCH", issue_endpoint,
            "-f", "state=closed", "-f", "state_reason=completed",
        ])

    if project_owner:
        project_env = os.environ.copy()
        if project_env.get("AUTOBOT_PROJECT_TOKEN"):
            project_env["GH_TOKEN"] = project_env["AUTOBOT_PROJECT_TOKEN"]
        warning = sync_project_stage(
            project_owner, project_number, project_status_field,
            issue["html_url"], "Done", env=project_env,
        )
        if warning:
            print(f"Autobot project sync failed: {warning}", file=sys.stderr)
            run([
                "gh", "issue", "comment", issue_number, "--repo", repository, "--body",
                "Autobot warning: the implementation PR is merged and this task is completed, "
                "but its Project stage could not be set to `Done`.\n\n"
                "Verify `AUTOBOT_PROJECT_OWNER`, `AUTOBOT_PROJECT_NUMBER`, "
                "`AUTOBOT_PROJECT_STATUS_FIELD` (including a `Done` option), and "
                "`AUTOBOT_PROJECT_TOKEN` project access/SSO. Then rerun the failed "
                "merge-completion job; it also repairs already-closed tasks.\n\n"
                f"Run: {os.environ.get('WORKFLOW_RUN_URL', '')}",
            ])
            raise PlanIssueError(f"task #{issue_number} completed, but Project sync failed")
    else:
        print("project sync skipped: no project owner/number configured")

    print(f"completed task #{issue_number} from merged PR #{pr_number}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pr-number", required=True, type=int)
    parser.add_argument("--default-branch", required=True)
    parser.add_argument("--project-owner", default="")
    parser.add_argument("--project-number", default="")
    parser.add_argument("--project-status-field", default="Status")
    args = parser.parse_args()
    try:
        complete_pr(
            args.repo, args.pr_number, args.default_branch,
            args.project_owner, args.project_number, args.project_status_field,
        )
    except (PlanIssueError, json.JSONDecodeError, KeyError, TypeError) as exc:
        print(f"Autobot merge completion failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
