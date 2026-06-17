#!/usr/bin/env node
// Print a compact owner approval brief for the local growth bundle.
//
// This is local/read-only. It summarizes current repo state, runs fast local
// launch guards, and prints the exact approval-gated commands. It never pushes,
// uploads, dispatches workflows, posts, comments, submits, pays, or uses account
// identity.

const childProcess = require("child_process");
const fs = require("fs");

const REPO = process.env.ACC_GROWTH_REPO || "maxbaluev/accreted-intelligence";
const BASE_REF = process.env.ACC_GROWTH_BASE_REF || "origin/main";
const GROWTH_REPORT = process.env.ACC_GROWTH_REPORT || "docs/ops/growth-report.md";

function usage() {
  console.error(`usage: node scripts/prepare-growth-approval-brief.js [--check|--markdown|--json] [tag]

Examples:
  node scripts/prepare-growth-approval-brief.js --check v0.1.6
  node scripts/prepare-growth-approval-brief.js --markdown v0.1.6
  ACC_GROWTH_REPORT=/path/to/NIGHT-REPORT.md node scripts/prepare-growth-approval-brief.js --markdown v0.1.6

Output is review material only. It does not push, upload, dispatch workflows,
publish registry metadata, post, comment, submit, pay, or use account identity.
`);
}

function die(message, code = 1) {
  console.error(`GROWTH APPROVAL BRIEF: ${message}`);
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

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
}

function readText(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (_) {
    return "";
  }
}

function growthReceipts() {
  const report = readText(GROWTH_REPORT);
  return {
    public_rollout_pushed: report.includes("| 2026-06-17 | Public repo |")
      && report.includes("`21a635e` pushed to `origin/main`"),
    hosted_live_verifier_passed: report.includes("| 2026-06-17 | Hosted live verifier |")
      && report.includes("Passed live attribution and LLM discovery checks"),
    controlled_live_install_passed: report.includes("| 2026-06-17 | Controlled live install |")
      && report.includes("Passed against the live installer stop path"),
    glama_listing_verified: report.includes("| 2026-06-17 | Glama MCP Registry |")
      && report.includes("Direct listing and score badge verify"),
    punkpeye_badge_branch_pushed: report.includes("| 2026-06-17 | punkpeye PR badge follow-up |")
      && report.includes("Owned branch pushed"),
    social_launch_receipt_recorded: /## Social launch receipts[\s\S]*\n\|\s*20\d\d-\d\d-\d\d\s*\|/.test(report),
  };
}

function normalizeTag(tag, serverVersion) {
  let result = tag || `v${serverVersion}`;
  if (!result.startsWith("v")) {
    result = `v${result}`;
  }
  return result;
}

function gitState() {
  const branch = run("git", ["branch", "--show-current"], { optional: true }) || "<detached>";
  const head = run("git", ["rev-parse", "--short", "HEAD"]);
  const headFull = run("git", ["rev-parse", "HEAD"]);
  const dirty = run("git", ["status", "--porcelain"], { optional: true });
  const hasBase = run("git", ["rev-parse", "--verify", BASE_REF], { optional: true });
  let ahead = "?";
  let behind = "?";
  if (hasBase) {
    ahead = run("git", ["rev-list", "--count", `${BASE_REF}..HEAD`], { optional: true }) || "?";
    behind = run("git", ["rev-list", "--count", `HEAD..${BASE_REF}`], { optional: true }) || "?";
  }
  return {
    branch,
    head,
    head_full: headFull,
    base_ref: BASE_REF,
    ahead,
    behind,
    clean: dirty.length === 0,
  };
}

function splitLines(text) {
  return String(text || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function unpublishedBundle(state) {
  const baseRef = state.base_ref || BASE_REF;
  const hasBase = run("git", ["rev-parse", "--verify", baseRef], { optional: true });
  if (!hasBase) {
    return {
      base_ref: baseRef,
      available: false,
      commits: [],
      files_changed: [],
      shortstat: "",
      reason: `base ref ${baseRef} is unavailable`,
    };
  }

  const range = `${baseRef}..HEAD`;
  const commits = splitLines(run("git", ["log", "--reverse", "--format=%h%x09%s", range], { optional: true }))
    .map((line) => {
      const [hash, ...subjectParts] = line.split("\t");
      return {
        hash,
        subject: subjectParts.join("\t"),
      };
    })
    .filter((commit) => commit.hash && commit.subject);
  const filesChanged = splitLines(run("git", ["diff", "--name-only", range], { optional: true }));
  const shortstat = run("git", ["diff", "--shortstat", range], { optional: true });

  return {
    base_ref: baseRef,
    available: true,
    commits,
    files_changed: filesChanged,
    shortstat,
  };
}

function runLocalChecks() {
  const checks = [
    ["node", ["scripts/check-site-metadata.js"]],
    ["node", ["scripts/check-social-launch-kit.js", "--check"]],
    ["node", ["scripts/prepare-social-launch-packet.js", "--check"]],
    ["node", ["scripts/prepare-social-launch-packet.js", "--decision-packet"]],
    ["node", ["scripts/prepare-social-launch-packet.js", "--reply-packet", "hn-show"]],
    ["node", ["scripts/prepare-social-launch-packet.js", "--receipt-packet", "hn-show", "https://example.com/accint-launch"]],
    ["node", ["scripts/check-attribution-flow.js"]],
    ["node", ["scripts/check-growth-surfaces.js", "--check"]],
    ["bash", ["scripts/check-controlled-install-attribution.sh"]],
    ["bash", ["scripts/check-install-surface.sh"]],
    ["node", ["scripts/prepare-posthog-dashboard.js", "--check"]],
    ["node", ["scripts/prepare-glama-submission-packet.js", "--check"]],
  ];
  const results = [];
  for (const [command, args] of checks) {
    const label = `${command} ${args.join(" ")}`;
    try {
      childProcess.execFileSync(command, args, { stdio: ["ignore", "ignore", "pipe"] });
      results.push({ label, ok: true });
    } catch (err) {
      const stderr = err.stderr ? String(err.stderr).trim() : "";
      results.push({ label, ok: false, detail: stderr });
    }
  }

  if (GROWTH_REPORT && fs.existsSync(GROWTH_REPORT)) {
    const directoryChecks = [
      ["node", ["scripts/prepare-directory-surface-refs.js", "--check", GROWTH_REPORT]],
      ["node", ["scripts/prepare-directory-followup-kit.js", "--check", "--actionable", GROWTH_REPORT]],
    ];
    for (const [command, args] of directoryChecks) {
      const label = `${command} ${args.join(" ")}`;
      try {
        childProcess.execFileSync(command, args, { stdio: ["ignore", "ignore", "pipe"] });
        results.push({ label, ok: true });
      } catch (err) {
        const stderr = err.stderr ? String(err.stderr).trim() : "";
        results.push({ label, ok: false, detail: stderr });
      }
    }
  }

  return results;
}

function exactActions(tag, branch, receipts, state) {
  const currentHeadPublished = receipts.public_rollout_pushed
    && state.ahead === "0"
    && state.behind === "0";
  const currentHeadLiveVerified = currentHeadPublished && receipts.hosted_live_verifier_passed;
  const currentHeadControlledInstallPassed = currentHeadLiveVerified && receipts.controlled_live_install_passed;
  return [
    {
      stage: "1",
      name: "Push local growth bundle and dispatch hosted live-site verifier",
      status: currentHeadPublished ? "completed" : "owner_approval_required",
      command: `ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh ${tag}`,
      expected_head: state.head_full,
      approval_scope: [
        `approved branch: ${branch}`,
        `approved head: ${state.head_full}`,
        `hosted verifier input: expected_head=${state.head_full}`,
      ],
      external_effects: [
        "git push origin main",
        `gh workflow run live-site-attribution.yml with expected_head=${state.head_full}`,
      ],
      guard: "Requires ACC_APPROVE_GROWTH_ROLLOUT=1",
    },
    {
      stage: "2",
      name: "Verify after deploy: attribution, PostHog proxy, and LLM discovery",
      status: currentHeadLiveVerified ? "completed" : "read_only_verification_required",
      command: `scripts/check-growth-live-state.sh ${tag}\nscripts/check-live-attribution-flow.sh https://accint.xyz\nscripts/check-live-llms-discovery.sh https://accint.xyz\nnode scripts/check-site-metadata.js`,
      external_effects: ["read-only public site/GitHub/PostHog proxy marker checks"],
      guard: "Read-only",
    },
    {
      stage: "3",
      name: "Controlled live install receipt proof",
      status: currentHeadControlledInstallPassed ? "completed" : "owner_approval_required",
      command: `ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh ${tag}`,
      external_effects: ["fetch live installer into temp home", "run attribution-only install stop path"],
      guard: "Requires ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1",
    },
    {
      stage: "4",
      name: "PostHog dashboard shell after owner supplies PostHog env",
      status: "owner_held_credentials",
      command: "POSTHOG_HOST=https://app.posthog.com POSTHOG_ENVIRONMENT_ID=<environment-id> POSTHOG_PERSONAL_API_KEY=<personal-api-key> ACC_APPROVE_POSTHOG_DASHBOARD=1 scripts/run-approved-posthog-dashboard.sh",
      external_effects: ["PostHog dashboard shell/setup tile creation"],
      guard: "Requires ACC_APPROVE_POSTHOG_DASHBOARD=1 and PostHog credentials",
    },
    {
      stage: "5",
      name: "PostHog aggregate funnel, direct refs, share loop, and Reddit community readout after dashboard/control install",
      status: "owner_held_credentials",
      command: "POSTHOG_HOST=https://us.posthog.com POSTHOG_PROJECT_ID=<project-id> POSTHOG_PERSONAL_API_KEY=<personal-api-key> ACC_APPROVE_POSTHOG_QUERY=1 scripts/run-approved-posthog-funnel-check.sh",
      external_effects: ["read-only aggregate PostHog Query API calls"],
      guard: "Requires ACC_APPROVE_POSTHOG_QUERY=1 and PostHog credentials",
    },
    {
      stage: "6",
      name: "Manual social launch posting",
      status: receipts.social_launch_receipt_recorded ? "completed" : "owner_target_selection_required",
      command: "node scripts/prepare-social-launch-packet.js --decision-packet",
      external_effects: ["owner manually posts selected HN/X/Reddit copy outside automation"],
      guard: "No automated posting; owner chooses exact target",
    },
    {
      stage: "7",
      name: "Owner-held Glama submission packet for punkpeye blocker",
      status: receipts.glama_listing_verified ? "completed" : "owner_submission_required",
      command: `node scripts/prepare-glama-submission-packet.js --form-packet ${tag}`,
      external_effects: ["owner may manually submit the Glama listing in a logged-in browser"],
      guard: "Packet is read-only; no automated Glama submission or PR badge update",
    },
  ].map((action) => ({ ...action, branch }));
}

function approvalBindingFailures(state, actions) {
  const failures = [];
  const rollout = actions.find((action) => String(action.stage) === "1");
  if (!/^[0-9a-f]{40}$/.test(state.head_full || "")) {
    failures.push("git state must expose the full 40-character HEAD SHA");
  }
  if (!rollout) {
    failures.push("approval sequence is missing rollout stage 1");
    return failures;
  }
  if (rollout.expected_head !== state.head_full) {
    failures.push("rollout stage 1 expected_head must match git HEAD");
  }
  if (!(rollout.approval_scope || []).some((item) => item.includes(`expected_head=${state.head_full}`))) {
    failures.push("rollout stage 1 approval scope must include the hosted verifier expected_head");
  }
  if (!(rollout.external_effects || []).some((item) => item.includes(`expected_head=${state.head_full}`))) {
    failures.push("rollout stage 1 external effects must mention the hosted verifier expected_head");
  }
  return failures;
}

function buildBrief(tag) {
  const server = readJson("server.json");
  const state = gitState();
  const bundle = unpublishedBundle(state);
  const checks = runLocalChecks();
  const receipts = growthReceipts();
  const actions = exactActions(tag, state.branch, receipts, state);
  const failures = checks.filter((check) => !check.ok);
  const validationFailures = approvalBindingFailures(state, actions);
  const hasUnpublishedBundle = state.ahead !== "0" && state.ahead !== "?";
  return {
    schema_version: 1,
    repo: REPO,
    tag,
    server_name: server.name || "",
    server_version: server.version || "",
    git: state,
    unpublished_bundle: bundle,
    growth_report: GROWTH_REPORT || null,
    growth_receipts: receipts,
    local_checks: checks,
    validation_failures: validationFailures,
    ready_for_owner_review: failures.length === 0 && validationFailures.length === 0 && state.clean && state.behind === "0" && state.ahead !== "0",
    exact_actions: actions,
    forbidden_without_approval: [
      "git push",
      "workflow dispatch",
      "release upload",
      "registry publish",
      "social post/comment/DM",
      "directory PR comment/edit/submit",
      "PostHog mutation/query with credentials",
      "payment/CAPTCHA/private account action",
    ],
    known_holds: [
      hasUnpublishedBundle
        ? `A new local bundle is ${state.ahead} commit(s) ahead of origin/main; push and hosted verifier dispatch still require fresh owner approval.`
        : receipts.public_rollout_pushed
        ? "Public rollout has already been pushed; do not repeat the guarded rollout unless a new local bundle is ahead of origin/main."
        : "Public rollout still requires owner approval before git push or hosted verifier dispatch.",
      receipts.glama_listing_verified
        ? "Glama direct listing and score badge verify, but Glama search indexing may lag."
        : "Glama listing/badge is still required before punkpeye badge branch update; use the Glama packet first, then the badge follow-up guard only after the listing is real.",
      receipts.punkpeye_badge_branch_pushed
        ? "punkpeye badge row has been pushed to the owned PR branch; the upstream PR remains maintainer-held."
        : "punkpeye badge branch update still requires a real Glama listing/badge and ACC_APPROVE_PUNKPEYE_GLAMA=1.",
      "PostHog dashboard/funnel and social posting require explicit owner approval and credentials/manual posting.",
    ],
  };
}

function printCheck(brief) {
  const checkFailures = brief.local_checks.filter((check) => !check.ok);
  const validationFailures = brief.validation_failures || [];
  if (checkFailures.length || validationFailures.length) {
    console.log("GROWTH APPROVAL BRIEF: FAIL");
    checkFailures.forEach((check) => console.log(`  FAIL: ${check.label}`));
    validationFailures.forEach((failure) => console.log(`  FAIL: ${failure}`));
    process.exit(1);
  }
  console.log("GROWTH APPROVAL BRIEF: PASS");
  console.log(`  repo: ${brief.repo}`);
  console.log(`  tag: ${brief.tag}`);
  console.log(`  branch: ${brief.git.branch} @ ${brief.git.head}`);
  console.log(`  approved head: ${brief.git.head_full}`);
  console.log(`  ahead/behind: ${brief.git.ahead}/${brief.git.behind}`);
  console.log(`  working tree: ${brief.git.clean ? "clean" : "dirty"}`);
  if (brief.unpublished_bundle && brief.unpublished_bundle.available) {
    console.log(`  unpublished commits: ${brief.unpublished_bundle.commits.length}`);
    console.log(`  unpublished files changed: ${brief.unpublished_bundle.files_changed.length}`);
  }
  console.log(`  exact approval actions: ${brief.exact_actions.length}`);
  console.log(`  ready for owner review: ${brief.ready_for_owner_review ? "yes" : "not yet"}`);
}

function printMarkdown(brief) {
  console.log("# Growth Approval Brief");
  console.log();
  console.log("READ ONLY: this brief does not push, upload, dispatch workflows, publish registry metadata, post, comment, submit, pay, or use account identity.");
  console.log();
  console.log("## Current State");
  console.log();
  console.log(`- Repo: \`${brief.repo}\``);
  console.log(`- Target tag: \`${brief.tag}\``);
  console.log(`- Registry server/version: \`${brief.server_name}\` / \`${brief.server_version}\``);
  console.log(`- Branch: \`${brief.git.branch}\` at \`${brief.git.head}\``);
  console.log(`- Approved HEAD: \`${brief.git.head_full}\``);
  console.log(`- Base: \`${brief.git.base_ref}\`, ahead/behind: \`${brief.git.ahead}/${brief.git.behind}\``);
  console.log(`- Working tree: ${brief.git.clean ? "clean" : "dirty"}`);
  if (brief.growth_report) {
    console.log(`- Growth report: \`${brief.growth_report}\``);
  }
  if (brief.unpublished_bundle) {
    console.log();
    console.log("## Unpublished Bundle");
    console.log();
    console.log(`- Base ref: \`${brief.unpublished_bundle.base_ref}\``);
    if (brief.unpublished_bundle.available) {
      console.log(`- Commits to push: ${brief.unpublished_bundle.commits.length}`);
      console.log(`- Files changed: ${brief.unpublished_bundle.files_changed.length}`);
      if (brief.unpublished_bundle.shortstat) {
        console.log(`- Diffstat: ${brief.unpublished_bundle.shortstat}`);
      }
      console.log();
      for (const commit of brief.unpublished_bundle.commits) {
        console.log(`- \`${commit.hash}\` ${commit.subject}`);
      }
    } else {
      console.log(`- Status: unavailable (${brief.unpublished_bundle.reason})`);
    }
  }
  console.log();
  console.log("## Local Checks");
  console.log();
  for (const check of brief.local_checks) {
    console.log(`- ${check.ok ? "PASS" : "FAIL"}: \`${check.label}\``);
  }
  console.log();
  console.log("## Approval Sequence");
  console.log();
  for (const action of brief.exact_actions) {
    console.log(`${action.stage}. ${action.name}`);
    console.log();
    console.log(`Status: \`${action.status || "unknown"}\``);
    if (action.expected_head) {
      console.log(`Expected hosted verifier HEAD: \`${action.expected_head}\``);
    }
    if (action.approval_scope && action.approval_scope.length) {
      console.log();
      console.log("Approval scope:");
      for (const item of action.approval_scope) {
        console.log(`- ${item}`);
      }
    }
    console.log();
    console.log("```bash");
    console.log(action.command);
    console.log("```");
    console.log();
    console.log(`Guard: ${action.guard}`);
    console.log(`External effect: ${action.external_effects.join("; ")}`);
    console.log();
  }
  console.log("## Known Holds");
  console.log();
  for (const hold of brief.known_holds) {
    console.log(`- ${hold}`);
  }
  console.log();
  console.log("## Forbidden Without Fresh Owner Approval");
  console.log();
  for (const item of brief.forbidden_without_approval) {
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

const server = readJson("server.json");
const tag = normalizeTag(args[0], server.version || "");
const brief = buildBrief(tag);

if (mode === "--json") {
  console.log(JSON.stringify(brief, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(brief);
} else {
  printCheck(brief);
}
