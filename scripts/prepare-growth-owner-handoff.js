#!/usr/bin/env node
// Print a compact owner handoff for the current growth rollout ask.
//
// This is local/read-only. It consumes the growth approval brief and decision
// queue, then reduces them to the single current owner decision, evidence, and
// immediate verification commands. It never pushes, uploads, dispatches
// workflows, publishes registry metadata, posts, comments, submits, pays, or
// uses account identity.

const childProcess = require("child_process");
const fs = require("fs");

const REQUIRED_FILES = [
  "server.json",
  "scripts/prepare-growth-approval-brief.js",
  "scripts/prepare-growth-decision-queue.js",
  "scripts/run-approved-growth-rollout.sh",
  "scripts/check-growth-live-state.sh",
  "scripts/check-live-attribution-flow.sh",
  "docs/ops/growth-rollout-checklist.md",
  "docs/ops/growth-report.md",
];

function usage() {
  console.error(`usage: node scripts/prepare-growth-owner-handoff.js [--check|--markdown|--json] [tag]

Examples:
  node scripts/prepare-growth-owner-handoff.js --check v0.1.6
  node scripts/prepare-growth-owner-handoff.js --markdown v0.1.6
  node scripts/prepare-growth-owner-handoff.js --json v0.1.6

Output is owner-review material only. It does not push, upload, dispatch
workflows, publish registry metadata, post, comment, submit, pay, or use account
identity.
`);
}

function die(message, code = 1) {
  console.error(`GROWTH OWNER HANDOFF: ${message}`);
  process.exit(code);
}

function run(command, args, options = {}) {
  try {
    return childProcess.execFileSync(command, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      ...options,
    }).trim();
  } catch (err) {
    if (options.optional) {
      return "";
    }
    const stderr = err.stderr ? String(err.stderr).trim() : "";
    die(`${command} ${args.join(" ")} failed${stderr ? `: ${stderr}` : ""}`);
  }
}

function readJsonFile(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
}

function readCommandJson(label, command, args) {
  const output = run(command, args);
  try {
    return JSON.parse(output);
  } catch (err) {
    die(`could not parse ${label} JSON: ${err.message}`);
  }
}

function normalizeTag(tag, serverVersion) {
  let result = tag || `v${serverVersion}`;
  if (!result.startsWith("v")) {
    result = `v${result}`;
  }
  return result;
}

function byStage(brief, stage) {
  return (brief.exact_actions || []).find((action) => String(action.stage) === String(stage)) || null;
}

function byRank(queue, rank) {
  return (queue.critical_path || []).find((item) => Number(item.rank) === Number(rank)) || null;
}

function missingFiles() {
  return REQUIRED_FILES.filter((file) => !fs.existsSync(file));
}

function commandBlock(command) {
  return String(command || "").trim();
}

function shortCommand(command) {
  return commandBlock(command).split(/\r?\n/)[0] || "<missing>";
}

function collectValidationFailures(brief, queue) {
  const failures = [];
  for (const file of missingFiles()) {
    failures.push(`missing required file: ${file}`);
  }
  for (const failure of queue.validation_failures || []) {
    failures.push(`decision queue: ${failure}`);
  }
  const rollout = byStage(brief, 1);
  const verification = byStage(brief, 2);
  if (!rollout) {
    failures.push("growth approval brief is missing rollout stage 1");
  }
  if (!verification) {
    failures.push("growth approval brief is missing verification stage 2");
  }
  if (!queue.top_decision) {
    failures.push("growth decision queue is missing a top decision");
  }
  if (rollout && queue.top_decision && commandBlock(rollout.command) !== commandBlock(queue.top_decision.command)) {
    failures.push("approval brief stage 1 command does not match decision queue top command");
  }
  return failures;
}

function summarizeChecks(brief) {
  const checks = brief.local_checks || [];
  const failed = checks.filter((check) => !check.ok);
  return {
    total: checks.length,
    passed: checks.length - failed.length,
    failed: failed.length,
    failures: failed.map((check) => check.label),
  };
}

function buildHandoff(tag) {
  const brief = readCommandJson("growth approval brief", "node", [
    "scripts/prepare-growth-approval-brief.js",
    "--json",
    tag,
  ]);
  const queue = readCommandJson("growth decision queue", "node", [
    "scripts/prepare-growth-decision-queue.js",
    "--json",
    tag,
  ]);
  const rollout = byStage(brief, 1) || {};
  const verification = byRank(queue, 2) || byStage(brief, 2) || {};
  const validationFailures = collectValidationFailures(brief, queue);
  const checkSummary = summarizeChecks(brief);
  const currentAsk = queue.top_decision || {
    action: rollout.name || "Approve public growth rollout",
    status: "missing_decision_queue",
    owner_decision: "Approve or hold the guarded public growth rollout.",
    command: rollout.command || "",
    guard: rollout.guard || "",
    why: "The growth bundle remains local until the owner approves the public rollout.",
  };

  return {
    schema_version: 1,
    repo: brief.repo,
    tag,
    server_name: brief.server_name,
    server_version: brief.server_version,
    git: brief.git,
    unpublished_bundle: brief.unpublished_bundle || null,
    growth_report: brief.growth_report || queue.growth_report || null,
    ready_for_owner_review: brief.ready_for_owner_review && queue.ready_for_owner_review && validationFailures.length === 0,
    current_ask: {
      action: currentAsk.action,
      status: currentAsk.status,
      owner_decision: currentAsk.owner_decision,
      command: commandBlock(currentAsk.command),
      guard: currentAsk.guard || rollout.guard || "",
      external_effects: rollout.external_effects || [],
      why: currentAsk.why || "",
      unlocks: currentAsk.unlocks || [],
    },
    evidence: {
      local_checks: checkSummary,
      approval_actions: (brief.exact_actions || []).length,
      critical_path_items: (queue.critical_path || []).length,
      branch_clean: Boolean(brief.git && brief.git.clean),
      branch_ahead: brief.git ? brief.git.ahead : "?",
      branch_behind: brief.git ? brief.git.behind : "?",
      unpublished_commits: brief.unpublished_bundle && brief.unpublished_bundle.available
        ? brief.unpublished_bundle.commits.length
        : null,
      unpublished_files_changed: brief.unpublished_bundle && brief.unpublished_bundle.available
        ? brief.unpublished_bundle.files_changed.length
        : null,
    },
    immediate_verification: {
      action: verification.action || verification.name || "Verify after deploy, no mutation",
      command: commandBlock(verification.command),
      guard: verification.guard || "Read-only",
    },
    later_owner_lanes: (queue.critical_path || [])
      .filter((item) => Number(item.rank) >= 3)
      .map((item) => ({
        rank: item.rank,
        action: item.action,
        status: item.status,
        guard: item.guard,
      })),
    known_holds: queue.known_holds || brief.known_holds || [],
    forbidden_without_approval: queue.forbidden_without_approval || brief.forbidden_without_approval || [],
    validation_failures: validationFailures,
  };
}

function printCheck(handoff) {
  if (handoff.validation_failures.length) {
    console.log("GROWTH OWNER HANDOFF: FAIL");
    for (const failure of handoff.validation_failures) {
      console.log(`  FAIL: ${failure}`);
    }
    process.exit(1);
  }
  console.log("GROWTH OWNER HANDOFF: PASS");
  console.log(`  repo: ${handoff.repo}`);
  console.log(`  tag: ${handoff.tag}`);
  console.log(`  branch: ${handoff.git.branch} @ ${handoff.git.head}`);
  console.log(`  ahead/behind: ${handoff.git.ahead}/${handoff.git.behind}`);
  console.log(`  working tree: ${handoff.git.clean ? "clean" : "dirty"}`);
  if (handoff.unpublished_bundle && handoff.unpublished_bundle.available) {
    console.log(`  unpublished commits: ${handoff.unpublished_bundle.commits.length}`);
    console.log(`  unpublished files changed: ${handoff.unpublished_bundle.files_changed.length}`);
  }
  console.log(`  ready for owner review: ${handoff.ready_for_owner_review ? "yes" : "not yet"}`);
  console.log(`  ask: ${handoff.current_ask.action}`);
  console.log(`  command: ${shortCommand(handoff.current_ask.command)}`);
  console.log(`  local checks: ${handoff.evidence.local_checks.passed}/${handoff.evidence.local_checks.total} passed`);
}

function printMarkdown(handoff) {
  console.log("# Growth Owner Handoff");
  console.log();
  console.log("READ ONLY: this handoff does not push, upload, dispatch workflows, publish registry metadata, post, comment, submit, pay, or use account identity.");
  console.log();
  console.log("## Current Ask");
  console.log();
  console.log(`- Decision: ${handoff.current_ask.owner_decision}`);
  console.log(`- Action: ${handoff.current_ask.action}`);
  console.log(`- Status: \`${handoff.current_ask.status}\``);
  console.log(`- Guard: ${handoff.current_ask.guard}`);
  console.log(`- Ready for owner review: ${handoff.ready_for_owner_review ? "yes" : "not yet"}`);
  if (handoff.current_ask.why) {
    console.log(`- Why now: ${handoff.current_ask.why}`);
  }
  console.log();
  console.log("Run only after explicit owner approval for this exact external action:");
  console.log();
  console.log("```bash");
  console.log(handoff.current_ask.command);
  console.log("```");
  console.log();
  console.log("This approved action would:");
  for (const effect of handoff.current_ask.external_effects) {
    console.log(`- ${effect}`);
  }
  if (!handoff.current_ask.external_effects.length) {
    console.log("- <no external effects listed>");
  }
  console.log();
  console.log("It would unlock:");
  for (const unlock of handoff.current_ask.unlocks) {
    console.log(`- ${unlock}`);
  }
  console.log();
  console.log("## Evidence");
  console.log();
  console.log(`- Repo: \`${handoff.repo}\``);
  console.log(`- Target tag: \`${handoff.tag}\``);
  console.log(`- Registry server/version: \`${handoff.server_name}\` / \`${handoff.server_version}\``);
  console.log(`- Branch: \`${handoff.git.branch}\` at \`${handoff.git.head}\``);
  console.log(`- Base: \`${handoff.git.base_ref}\`, ahead/behind: \`${handoff.git.ahead}/${handoff.git.behind}\``);
  console.log(`- Working tree: ${handoff.git.clean ? "clean" : "dirty"}`);
  console.log(`- Local checks: ${handoff.evidence.local_checks.passed}/${handoff.evidence.local_checks.total} passed`);
  console.log(`- Approval actions: ${handoff.evidence.approval_actions}`);
  console.log(`- Critical path items: ${handoff.evidence.critical_path_items}`);
  if (handoff.growth_report) {
    console.log(`- Growth report: \`${handoff.growth_report}\``);
  }
  console.log();
  if (handoff.unpublished_bundle) {
    console.log("## Unpublished Bundle To Push");
    console.log();
    console.log(`- Base ref: \`${handoff.unpublished_bundle.base_ref}\``);
    if (handoff.unpublished_bundle.available) {
      console.log(`- Commits: ${handoff.unpublished_bundle.commits.length}`);
      console.log(`- Files changed: ${handoff.unpublished_bundle.files_changed.length}`);
      if (handoff.unpublished_bundle.shortstat) {
        console.log(`- Diffstat: ${handoff.unpublished_bundle.shortstat}`);
      }
      console.log();
      for (const commit of handoff.unpublished_bundle.commits) {
        console.log(`- \`${commit.hash}\` ${commit.subject}`);
      }
    } else {
      console.log(`- Status: unavailable (${handoff.unpublished_bundle.reason})`);
    }
    console.log();
  }
  console.log("## Immediate Verification After Approval");
  console.log();
  console.log(`- Action: ${handoff.immediate_verification.action}`);
  console.log(`- Guard: ${handoff.immediate_verification.guard}`);
  console.log();
  console.log("```bash");
  console.log(handoff.immediate_verification.command);
  console.log("```");
  console.log();
  console.log("## Later Owner-Held Lanes");
  console.log();
  for (const lane of handoff.later_owner_lanes) {
    console.log(`- ${lane.rank}. ${lane.action} — \`${lane.status}\` (${lane.guard})`);
  }
  console.log();
  console.log("## Known Holds");
  console.log();
  for (const hold of handoff.known_holds) {
    console.log(`- ${hold}`);
  }
  console.log();
  console.log("## Still Forbidden Without Fresh Owner Approval");
  console.log();
  for (const item of handoff.forbidden_without_approval) {
    console.log(`- ${item}`);
  }
}

const args = process.argv.slice(2);
let mode = "--check";
if (args[0] === "-h" || args[0] === "--help") {
  usage();
  process.exit(0);
}
if (["--check", "--markdown", "--json"].includes(args[0])) {
  mode = args.shift();
}
if (!["--check", "--markdown", "--json"].includes(mode)) {
  usage();
  process.exit(2);
}

const server = readJsonFile("server.json");
const tag = normalizeTag(args[0], server.version || "");
const handoff = buildHandoff(tag);

if (mode === "--json") {
  console.log(JSON.stringify(handoff, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(handoff);
} else {
  printCheck(handoff);
}
