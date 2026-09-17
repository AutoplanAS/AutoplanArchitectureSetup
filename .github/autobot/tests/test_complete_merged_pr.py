from __future__ import annotations

import contextlib
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import complete_merged_pr as completion
import create_plan_issues


def lifecycle_group(workflow_name):
    path = SCRIPTS.parents[2] / ".github" / "workflows" / workflow_name
    workflow = path.read_text(encoding="utf-8")
    group = re.search(r"^\s+group: (.+)$", workflow, re.MULTILINE).group(1)
    return (
        group.replace("${{ inputs.repository }}", "org/repo")
        .replace("${{ inputs.issue_number }}", "42")
        .replace("${{ needs.resolve.outputs.issue_number }}", "42")
    )


class FakeGitHub:
    def __init__(self):
        self.pr = {
            "merged": True,
            "state": "closed",
            "base": {"ref": "main"},
            "head": {"ref": "autobot/42-task-title", "repo": {"full_name": "org/repo"}},
        }
        self.issue = {
            "state": "open",
            "state_reason": None,
            "html_url": "https://github.com/org/repo/issues/42",
            "labels": [
                {"name": name}
                for name in ("autobot-task", "autoboot", "autobot-in-review", "team-owned")
            ],
        }
        self.calls = []
        self.fail_at = None
        self.error = "simulated API failure"
        self.project_stage = "In review"

    def run(self, command, **kwargs):
        self.calls.append((command, kwargs.get("env") or os.environ.copy()))
        operation = command[1:3]
        if operation == self.fail_at:
            return subprocess.CompletedProcess(command, 1, "", self.error)
        output = ""
        if operation == ["api", "repos/org/repo/pulls/10"]:
            output = json.dumps(self.pr)
        elif operation == ["api", "repos/org/repo/issues/42"]:
            output = json.dumps(self.issue)
        elif operation == ["label", "create"]:
            assert command[3] == "autobot-done"
        elif operation == ["issue", "edit"]:
            assert command[3] == "42"
            labels = self.labels()
            for index, value in enumerate(command):
                if value == "--remove-label":
                    labels.discard(command[index + 1])
                elif value == "--add-label":
                    labels.add(command[index + 1])
            self.issue["labels"] = [{"name": label} for label in sorted(labels)]
        elif operation == ["api", "--method"]:
            assert command[3:] == [
                "PATCH", "repos/org/repo/issues/42",
                "-f", "state=closed", "-f", "state_reason=completed",
            ]
            self.issue.update(state="closed", state_reason="completed")
        elif operation == ["project", "item-add"]:
            output = '{"id":"PVTI_item"}'
        elif operation == ["project", "item-edit"]:
            self.project_stage = command[command.index("--value") + 1]
        elif operation == ["issue", "comment"]:
            assert command[3] == "42"
        else:
            raise AssertionError(f"Unexpected command: {command}")
        return subprocess.CompletedProcess(command, 0, output, "")

    def labels(self):
        return {label["name"] for label in self.issue["labels"]}

    def operations(self):
        return [command[1:3] for command, _ in self.calls]


class CompletionTests(unittest.TestCase):
    def setUp(self):
        self.github = FakeGitHub()
        self.patch = patch.object(create_plan_issues.subprocess, "run", self.github.run)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.output = io.StringIO()
        self.stdout = contextlib.redirect_stdout(self.output)
        self.stdout.__enter__()
        self.addCleanup(self.stdout.__exit__, None, None, None)
        self.stderr = contextlib.redirect_stderr(self.output)
        self.stderr.__enter__()
        self.addCleanup(self.stderr.__exit__, None, None, None)

    def complete(self, **kwargs):
        return completion.complete_pr("org/repo", 10, "main", **kwargs)

    def test_merge_completes_only_task_and_preserves_nonphase_labels(self):
        self.github.issue["labels"].extend(
            {"name": label} for label in completion.PHASE_LABELS
        )
        self.assertTrue(self.complete(project_owner="org", project_number="8"))
        self.assertEqual(
            self.github.labels(), {"autobot-task", "autoboot", "team-owned", "autobot-done"}
        )
        self.assertEqual(self.github.issue["state"], "closed")
        self.assertEqual(self.github.issue["state_reason"], "completed")
        self.assertEqual(self.github.project_stage, "Done")

    def test_approval_without_merge_does_not_complete(self):
        self.github.pr.update(merged=False, state="open", reviewDecision="APPROVED")
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 1)

    def test_closed_without_merge_does_not_complete(self):
        self.github.pr["merged"] = False
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 1)

    def test_merge_into_nondefault_branch_is_ignored(self):
        self.github.pr["base"]["ref"] = "release"
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 1)

    def test_custom_default_branch_is_supported(self):
        self.github.pr["base"]["ref"] = "trunk"
        self.assertTrue(completion.complete_pr("org/repo", 10, "trunk"))

    def test_fork_and_deleted_head_repository_are_ignored(self):
        for head_repo in ({"full_name": "outsider/repo"}, None):
            with self.subTest(head_repo=head_repo):
                self.github.pr["head"]["repo"] = head_repo
                self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 2)

    def test_repository_comparison_is_case_insensitive(self):
        self.github.pr["head"]["repo"]["full_name"] = "ORG/Repo"
        self.assertTrue(self.complete())

    def test_unrelated_and_planning_branches_are_ignored(self):
        for branch in (
            "feature/task", "autobot-plan/42-title", "autobot/0-title",
            "autobot/42-", "autobot/42-title/extra", "autobot/42-title;command",
        ):
            with self.subTest(branch=branch):
                self.github.pr["head"]["ref"] = branch
                self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 6)

    def test_spec_or_parent_issue_is_not_completed(self):
        self.github.issue["labels"] = [{"name": "autobot-in-review"}]
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 2)

    def test_pr_number_cannot_be_treated_as_task_issue(self):
        self.github.issue["pull_request"] = {"url": "https://api.github.com/repos/org/repo/pulls/42"}
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 2)

    def test_task_must_have_reached_review(self):
        self.github.issue["labels"] = [
            {"name": name} for name in ("autobot-task", "autobot-implementing")
        ]
        self.assertFalse(self.complete())
        self.assertEqual(len(self.github.calls), 2)

    def test_pr_body_does_not_select_additional_issues(self):
        self.github.pr["body"] = "Closes #99 and other/repo#42"
        self.assertTrue(self.complete())
        self.assertNotIn("#99", str(self.github.calls))
        self.assertNotIn("other/repo", str(self.github.calls))

    def test_autoclosed_issue_still_gets_label_and_project_stage(self):
        self.github.issue.update(state="closed", state_reason="completed")
        self.assertTrue(self.complete(project_owner="org", project_number="8"))
        self.assertIn("autobot-done", self.github.labels())
        self.assertEqual(self.github.project_stage, "Done")
        self.assertNotIn(["api", "--method"], self.github.operations())

    def test_closed_issue_with_wrong_reason_is_corrected(self):
        self.github.issue.update(state="closed", state_reason="not_planned")
        self.assertTrue(self.complete())
        self.assertEqual(self.github.issue["state_reason"], "completed")

    def test_repeated_event_repairs_project_without_repeating_issue_writes(self):
        self.complete(project_owner="org", project_number="8")
        self.github.calls.clear()
        self.github.project_stage = "In review"
        self.assertTrue(self.complete(project_owner="org", project_number="8"))
        self.assertEqual(self.github.operations(), [
            ["api", "repos/org/repo/pulls/10"], ["api", "repos/org/repo/issues/42"],
            ["project", "item-add"], ["project", "item-edit"],
        ])
        self.assertEqual(self.github.project_stage, "Done")

    def test_label_failure_prevents_closure_and_project_sync(self):
        self.github.fail_at = ["issue", "edit"]
        with self.assertRaisesRegex(completion.PlanIssueError, "simulated API failure"):
            self.complete(project_owner="org", project_number="8")
        self.assertEqual(self.github.issue["state"], "open")
        self.assertNotIn("autobot-done", self.github.labels())
        self.assertNotIn(["project", "item-add"], self.github.operations())

    def test_retry_recovers_after_label_succeeds_but_closure_fails(self):
        self.github.fail_at = ["api", "--method"]
        with self.assertRaises(completion.PlanIssueError):
            self.complete()
        self.assertIn("autobot-done", self.github.labels())
        self.assertEqual(self.github.issue["state"], "open")
        self.github.fail_at = None
        self.assertTrue(self.complete())
        self.assertEqual(self.github.issue["state"], "closed")

    def test_project_failures_are_visible_and_retryable(self):
        for operation in (["project", "item-add"], ["project", "item-edit"]):
            with self.subTest(operation=operation):
                self.github.fail_at = operation
                with self.assertRaisesRegex(completion.PlanIssueError, "Project sync failed"):
                    self.complete(project_owner="org", project_number="8")
                self.assertEqual(self.github.issue["state"], "closed")
                self.assertIn(["issue", "comment"], self.github.operations())
                self.assertIn("simulated API failure", self.output.getvalue())
                self.github.fail_at = None
                self.assertTrue(self.complete(project_owner="org", project_number="8"))
                self.assertEqual(self.github.project_stage, "Done")

    def test_already_added_project_item_is_supported(self):
        self.github.fail_at = ["project", "item-add"]
        self.github.error = "item already exists"
        self.assertTrue(self.complete(project_owner="org", project_number="8"))
        self.assertEqual(self.github.project_stage, "Done")

    def test_project_token_is_only_used_for_project_commands(self):
        with patch.dict(os.environ, {
            "GH_TOKEN": "repository-token",
            "AUTOBOT_PROJECT_TOKEN": "project-token",
        }):
            self.complete(project_owner="org", project_number="8", project_status_field="Phase")
            self.assertEqual(os.environ["GH_TOKEN"], "repository-token")
        for command, env in self.github.calls:
            expected = "project-token" if command[1] == "project" else "repository-token"
            self.assertEqual(env["GH_TOKEN"], expected)
        edit = next(command for command, _ in self.github.calls if command[1:3] == ["project", "item-edit"])
        self.assertEqual(edit[edit.index("--field") + 1], "Phase")

    def test_project_uses_repository_token_when_no_project_token(self):
        with patch.dict(os.environ, {"GH_TOKEN": "repository-token", "AUTOBOT_PROJECT_TOKEN": ""}):
            self.complete(project_owner="org", project_number="8")
        for _, env in self.github.calls:
            self.assertEqual(env["GH_TOKEN"], "repository-token")

    def test_shared_project_helper_remains_compatible_without_env_argument(self):
        warning = create_plan_issues.sync_project_stage(
            "org", "8", "Status", self.github.issue["html_url"], "Done"
        )
        self.assertIsNone(warning)
        self.assertEqual(self.github.project_stage, "Done")

    def test_no_project_configuration_is_an_explicit_skip(self):
        self.assertTrue(self.complete())
        self.assertIn("project sync skipped", self.output.getvalue())
        self.assertFalse(any(command[1] == "project" for command, _ in self.github.calls))

    def test_partial_or_invalid_project_configuration_fails_before_mutations(self):
        for kwargs in (
            {"project_owner": "org"}, {"project_number": "8"},
            {"project_owner": "org", "project_number": "-1"},
        ):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(completion.PlanIssueError):
                    self.complete(**kwargs)
        self.assertEqual(self.github.calls, [])

    def test_api_failure_is_not_treated_as_ineligible(self):
        self.github.fail_at = ["api", "repos/org/repo/pulls/10"]
        with self.assertRaises(completion.PlanIssueError):
            self.complete()
        self.assertEqual(len(self.github.calls), 1)

    def test_delayed_issue_poller_write_cannot_follow_merge_completion(self):
        groups = {
            name: lifecycle_group(name)
            for name in ("autobot-implement.yml", "autobot-complete.yml")
        }
        locks = {group: threading.Lock() for group in groups.values()}
        acceptance_started = threading.Event()
        release_acceptance = threading.Event()
        merge_attempted = threading.Event()
        merge_entered = threading.Event()

        def delayed_issue_poller():
            with locks[groups["autobot-implement.yml"]]:
                acceptance_started.set()
                if not release_acceptance.wait(5):
                    raise AssertionError("test did not release acceptance")
                return create_plan_issues.sync_project_stage(
                    "org", "8", "Status", self.github.issue["html_url"], "In review"
                )

        def merged_pr_event():
            merge_attempted.set()
            with locks[groups["autobot-complete.yml"]]:
                merge_entered.set()
                return self.complete(project_owner="org", project_number="8")

        with ThreadPoolExecutor(max_workers=2) as executor:
            poller = executor.submit(delayed_issue_poller)
            self.assertTrue(acceptance_started.wait(5))
            merged = executor.submit(merged_pr_event)
            try:
                self.assertTrue(merge_attempted.wait(5))
                self.assertFalse(merge_entered.wait(0.1))
            finally:
                release_acceptance.set()
            self.assertIsNone(poller.result(timeout=5))
            self.assertTrue(merged.result(timeout=5))
        self.assertEqual(self.github.project_stage, "Done")
        self.assertIn("autobot-done", self.github.labels())

    def test_entrypoint_returns_failure_for_malformed_api_data(self):
        del self.github.pr["merged"]
        with patch.object(sys, "argv", [
            "complete_merged_pr.py", "--repo", "org/repo", "--pr-number", "10",
            "--default-branch", "main",
        ]):
            self.assertEqual(completion.main(), 1)
        self.assertIn("Autobot merge completion failed", self.output.getvalue())


class WorkflowContractTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[3]

    def test_consumer_router_matches_local_router(self):
        local = (self.root / ".github/workflows/autobot.yml").read_text(encoding="utf-8")
        consumer = (self.root / ".github/autobot/examples/autobot.yml").read_text(encoding="utf-8")
        normalized = consumer.replace(
            "AutoplanAS/AutoplanArchitectureSetup/.github/workflows/",
            "./.github/workflows/",
        ).replace(".yml@v1", ".yml")
        self.assertEqual(local, normalized)

    def test_merge_route_is_closed_merged_default_branch_and_same_repository_only(self):
        router = (self.root / ".github/workflows/autobot.yml").read_text(encoding="utf-8")
        self.assertIn("pull_request_target:\n    types: [closed]", router)
        job = router.split("  merge-complete:\n", 1)[1].split("  copilot-complete:\n", 1)[0]
        for guard in (
            "github.event_name == 'pull_request_target'",
            "github.event.pull_request.merged == true",
            "github.event.pull_request.base.ref == github.event.repository.default_branch",
            "github.event.pull_request.head.repo.full_name == github.repository",
        ):
            self.assertIn(guard, job)

    def test_completion_only_checks_out_trusted_baseline_and_does_not_persist_credentials(self):
        workflow = (self.root / ".github/workflows/autobot-complete.yml").read_text(encoding="utf-8")
        self.assertEqual(workflow.count("uses: actions/checkout@"), 1)
        self.assertIn("vars.AUTOBOT_BASELINE_REPOSITORY", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertNotIn("github.event.pull_request.head", workflow)
        checkout = workflow.split("      - name: Checkout trusted baseline tooling only", 1)[1]
        self.assertNotIn("repository: ${{ inputs.repository }}", checkout)

    def test_all_issue_writers_share_one_noncancelling_lifecycle_group(self):
        for name in (
            "autobot-complete.yml", "autobot-copilot-complete.yml", "autobot-implement.yml",
            "autobot-plan.yml", "autobot-spec.yml", "autobot-project-sync.yml",
        ):
            workflow = (self.root / ".github/workflows" / name).read_text(encoding="utf-8")
            self.assertEqual(lifecycle_group(name), "autobot-org/repo-42", name)
            self.assertIn("cancel-in-progress: false", workflow)
            self.assertIn("queue: max", workflow)

    def test_pr_writers_resolve_issue_before_locking(self):
        for name in ("autobot-complete.yml", "autobot-copilot-complete.yml"):
            workflow = (self.root / ".github/workflows" / name).read_text(encoding="utf-8")
            self.assertIn("uses: ./.github/workflows/autobot-pr-issue.yml", workflow)
            self.assertIn("    needs: resolve\n    if: needs.resolve.outputs.issue_number != ''", workflow)
            self.assertIn("    concurrency:\n      group:", workflow)

    def test_queued_label_sync_preserves_current_terminal_state(self):
        workflow = (self.root / ".github/workflows/autobot-project-sync.yml").read_text(encoding="utf-8")
        self.assertIn('any(.labels[]; .name == "autobot-done")', workflow)
        self.assertIn('if [[ "$terminal" == "true" ]]; then\n            PROJECT_STAGE="Done"', workflow)
        self.assertLess(workflow.index('terminal="$(gh api'), workflow.index("gh project item-edit"))

    def test_closed_handoff_guard_precedes_branch_fetch_and_side_effects(self):
        script = (SCRIPTS / "run_copilot_completion_phase.sh").read_text(encoding="utf-8")
        self.assertLess(script.index('if [[ "$pr_state" != "OPEN" ]]'), script.index("git fetch"))
        self.assertLess(script.index("grep -Fxq autobot-done"), script.index("git fetch"))

    def test_late_handoff_event_for_closed_pr_exits_without_git_or_issue_writes(self):
        script = SCRIPTS / "run_copilot_completion_phase.sh"
        command = """
set -euo pipefail
gh() {
  if [[ "$1" == pr && "$2" == view ]]; then
    printf '{"state":"MERGED"}'
  else
    echo "unexpected GitHub write" >&2
    return 99
  fi
}
git() { echo "unexpected git command" >&2; return 99; }
export -f gh git
export REPOSITORY=org/repo PR_NUMBER=10 DEFAULT_BRANCH=main
bash "$1"
"""
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["bash", "-c", command, "test", script.as_posix()],
                cwd=directory, text=True, capture_output=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("is no longer open", result.stdout)


if __name__ == "__main__":
    unittest.main()
