#!/usr/bin/env node
// Print the dependency-aware owner decision queue for the growth rollout.
//
// This is local/read-only. It consumes the compact approval brief and turns the
// exact approval actions into an ordered critical path. It never pushes, uploads,
// dispatches workflows, publishes registry metadata, posts, comments, submits,
// pays, or uses account identity.

const childProcess = require("child_process");
const fs = require("fs");

const REQUIRED_FILES = [
  "server.json",
  "docs/ops/growth-report.md",
  "docs/ops/growth-rollout-checklist.md",
  "scripts/prepare-growth-approval-brief.js",
  "scripts/run-approved-growth-rollout.sh",
  "scripts/check-growth-live-state.sh",
  "scripts/check-live-attribution-flow.sh",
  "scripts/check-live-llms-discovery.sh",
  "scripts/run-approved-controlled-live-install.sh",
  "scripts/prepare-posthog-dashboard.js",
  "scripts/run-approved-posthog-dashboard.sh",
  "scripts/run-approved-posthog-funnel-check.sh",
  "scripts/prepare-social-launch-packet.js",
  "scripts/check-social-launch-kit.js",
  "scripts/prepare-directory-priority-report.js",
  "scripts/prepare-directory-followup-kit.js",
  "scripts/prepare-directory-surface-refs.js",
  "scripts/prepare-glama-submission-packet.js",
  "scripts/prepare-punkpeye-glama-followup.sh",
];

function usage() {
  console.error(`usage: node scripts/prepare-growth-decision-queue.js [--check|--markdown|--json] [tag]

Examples:
  node scripts/prepare-growth-decision-queue.js --check v0.1.6
  node scripts/prepare-growth-decision-queue.js --markdown v0.1.6
  node scripts/prepare-growth-decision-queue.js --json v0.1.6

Output is owner-review material only. It does not push, upload, dispatch
workflows, publish registry metadata, post, comment, submit, pay, or use account
identity.
`);
}

function die(message, code = 1) {
  console.error(`GROWTH DECISION QUEUE: ${message}`);
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

function normalizeTag(tag, serverVersion) {
  let result = tag || `v${serverVersion}`;
  if (!result.startsWith("v")) {
    result = `v${result}`;
  }
  return result;
}

function readApprovalBrief(tag) {
  const output = run("node", ["scripts/prepare-growth-approval-brief.js", "--json", tag]);
  try {
    return JSON.parse(output);
  } catch (err) {
    die(`could not parse growth approval brief JSON: ${err.message}`);
  }
}

function stage(brief, stageNumber) {
  return brief.exact_actions.find((action) => String(action.stage) === String(stageNumber)) || null;
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

function byRank(queue, rank) {
  return (queue || []).find((item) => Number(item.rank) === Number(rank)) || null;
}

function queueItem(rank, item) {
  return {
    rank,
    action: item.action,
    status: item.status,
    owner_decision: item.owner_decision || "",
    command: commandBlock(item.command),
    guard: item.guard,
    expected_head: item.expected_head || "",
    approval_scope: item.approval_scope || [],
    depends_on: item.depends_on || [],
    unlocks: item.unlocks || [],
    external_effects: item.external_effects || [],
    why: item.why,
  };
}

function validationFailures(brief) {
  const failures = [];
  for (const file of missingFiles()) {
    failures.push(`missing required file: ${file}`);
  }
  for (const check of brief.local_checks.filter((item) => !item.ok)) {
    failures.push(`local check failed: ${check.label}`);
  }
  if (!Array.isArray(brief.exact_actions) || brief.exact_actions.length < 7) {
    failures.push("growth approval brief did not expose the expected approval actions");
  }
  for (const number of ["1", "2", "3", "4", "5", "6", "7"]) {
    if (!stage(brief, number)) {
      failures.push(`growth approval brief is missing stage ${number}`);
    }
  }
  const rollout = stage(brief, "1");
  if (!/^[0-9a-f]{40}$/.test((brief.git && brief.git.head_full) || "")) {
    failures.push("growth approval brief must expose git.head_full for exact owner approval");
  }
  if (rollout && rollout.expected_head !== brief.git.head_full) {
    failures.push("growth approval brief stage 1 expected_head must match git.head_full");
  }
  return failures;
}

function queueValidationFailures(queue) {
  const failures = [];
  const socialLaunch = byRank(queue, 7);
  if (!socialLaunch) {
    failures.push("decision queue is missing the manual social launch lane");
    return failures;
  }

  const socialCommand = commandBlock(socialLaunch.command);
  for (const requiredMode of ["--decision-packet", "--receipt-packet", "--reply-packet"]) {
    if (!socialCommand.includes(requiredMode)) {
      failures.push(`manual social launch lane must include ${requiredMode}`);
    }
  }
  if (!socialLaunch.unlocks.some((unlock) => unlock.includes("Social launch receipts"))) {
    failures.push("manual social launch lane must unlock Social launch receipts accounting");
  }
  return failures;
}

function buildQueue(brief, tag) {
  const receipts = brief.growth_receipts || {};
  const currentHeadPublished = receipts.public_rollout_pushed
    && brief.git.ahead === "0"
    && brief.git.behind === "0";
  const currentHeadLiveVerified = currentHeadPublished && receipts.hosted_live_verifier_passed;
  const currentHeadControlledInstallPassed = currentHeadLiveVerified && receipts.controlled_live_install_passed;
  const localFailures = brief.local_checks.filter((item) => !item.ok);
  const rolloutBlockers = [];
  if (localFailures.length) {
    rolloutBlockers.push("local launch guards must pass");
  }
  if (!brief.git.clean) {
    rolloutBlockers.push("working tree must be clean");
  }
  if (brief.git.behind !== "0") {
    rolloutBlockers.push(`branch must not be behind ${brief.git.base_ref}`);
  }
  if (brief.git.ahead === "0") {
    rolloutBlockers.push(`branch must contain a local growth bundle ahead of ${brief.git.base_ref}`);
  }
  if (brief.git.ahead === "?") {
    rolloutBlockers.push(`branch position against ${brief.git.base_ref} is unknown`);
  }

  const rolloutReady = rolloutBlockers.length === 0;
  const action1 = stage(brief, "1") || {};
  const action2 = stage(brief, "2") || {};
  const action3 = stage(brief, "3") || {};
  const action4 = stage(brief, "4") || {};
  const action5 = stage(brief, "5") || {};
  const action6 = stage(brief, "6") || {};
  const action7 = stage(brief, "7") || {};
  const socialLaunchCommand = [
    action6.command || "node scripts/prepare-social-launch-packet.js --decision-packet",
    "node scripts/prepare-social-launch-packet.js --receipt-packet <surface-ref> <published-url>",
    "node scripts/prepare-social-launch-packet.js --reply-packet <surface-ref>",
  ].join("\n");

  return [
    queueItem(1, {
      action: "Approve public growth rollout",
      status: currentHeadPublished ? "completed" : (rolloutReady ? "ready_for_owner_approval" : "blocked"),
      owner_decision: `Approve or hold the guarded push plus hosted verifier dispatch for ${brief.git.head_full}.`,
      command: action1.command,
      guard: action1.guard || "Requires ACC_APPROVE_GROWTH_ROLLOUT=1",
      expected_head: action1.expected_head || brief.git.head_full,
      approval_scope: action1.approval_scope || [
        `approved branch: ${brief.git.branch}`,
        `approved head: ${brief.git.head_full}`,
        `hosted verifier input: expected_head=${brief.git.head_full}`,
      ],
      depends_on: currentHeadPublished
        ? ["current HEAD is published at origin/main and receipt row confirms public rollout was pushed"]
        : (rolloutReady ? [`Owner approval for this exact external action and approved HEAD ${brief.git.head_full}`] : rolloutBlockers),
      unlocks: [
        "publishes the local growth bundle",
        "makes README, live-site attribution, and llms.txt discovery changes observable",
        "dispatches the hosted live-site verifier after GitHub indexes the workflow",
      ],
      external_effects: action1.external_effects || ["git push origin main", "gh workflow run live-site-attribution.yml"],
      why: "This is the highest leverage unlock because the current bundle is local-only until it is pushed.",
    }),
    queueItem(2, {
      action: "Verify live deploy, attribution, PostHog proxy, and LLM discovery",
      status: currentHeadLiveVerified ? "completed" : "waiting_on_rollout",
      owner_decision: "No mutation; run immediately after the approved rollout completes.",
      command: action2.command,
      guard: action2.guard || "Read-only",
      depends_on: currentHeadLiveVerified
        ? ["current HEAD is published and hosted verifier receipt row confirms live attribution, PostHog proxy, and llms discovery passed"]
        : [
          "step 1 completed",
          "GitHub Pages/site deployment visible for the target commit",
        ],
      unlocks: [
        "evidence that install copy carries attribution",
        "evidence that browser PostHog traffic is routed through the managed proxy",
        "evidence that llms.txt agent discovery is served and advertised",
        "safe basis for social, directory, and controlled-install follow-up",
      ],
      external_effects: action2.external_effects || ["read-only public site/GitHub checks"],
      why: "Promotion should point at a verified live surface instead of an assumed deployment.",
    }),
    queueItem(3, {
      action: "Prove controlled live install receipt",
      status: currentHeadControlledInstallPassed ? "completed" : "waiting_on_verified_live_site",
      owner_decision: "Approve the controlled live install helper only after the live site is verified.",
      command: action3.command,
      guard: action3.guard || "Requires ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1",
      depends_on: currentHeadControlledInstallPassed
        ? ["current HEAD is live verified and controlled live install receipt row exists"]
        : [
          "step 2 verified live attribution, PostHog proxy, and LLM discovery",
          "owner approval for the controlled live install helper",
        ],
      unlocks: [
        "receipt-level proof for first-run attribution",
        "a concrete event to inspect in PostHog",
      ],
      external_effects: action3.external_effects || ["fetch live installer into temp home", "run attribution-only install stop path"],
      why: "This converts launch copy into an inspectable install-attribution proof without a full install.",
    }),
    queueItem(4, {
      action: "Submit the Glama listing packet manually",
      status: receipts.glama_listing_verified ? "completed" : "owner_held_after_rollout",
      owner_decision: "Owner submits manually in Glama if the listing target is acceptable.",
      command: action7.command,
      guard: action7.guard || "Read-only packet; owner performs any browser submission manually",
      depends_on: receipts.glama_listing_verified
        ? ["Glama direct listing and score badge receipt row exists"]
        : [
          "step 1 pushed if packet fields depend on local growth assets",
          "owner logged-in browser decision for Glama",
        ],
      unlocks: [
        "real Glama listing URL",
        "Glama score badge prerequisite for punkpeye/awesome-mcp-servers#8091",
      ],
      external_effects: action7.external_effects || ["owner may manually submit the Glama listing in a logged-in browser"],
      why: "The highest-reach open MCP directory follow-up is blocked on a real Glama listing and badge.",
    }),
    queueItem(5, {
      action: "Update punkpeye Glama badge branch only after READY",
      status: receipts.punkpeye_badge_branch_pushed ? "completed" : "blocked_on_real_glama_listing",
      owner_decision: "Approve the badge branch update only after the guard reports READY.",
      command: `scripts/prepare-punkpeye-glama-followup.sh\nACC_APPROVE_PUNKPEYE_GLAMA=1 scripts/prepare-punkpeye-glama-followup.sh`,
      guard: "Requires a real Glama listing, a real Glama score badge, and ACC_APPROVE_PUNKPEYE_GLAMA=1",
      depends_on: receipts.punkpeye_badge_branch_pushed
        ? ["punkpeye badge follow-up receipt row exists"]
        : [
          "step 4 real Glama listing exists",
          "scripts/prepare-punkpeye-glama-followup.sh reports READY",
        ],
      unlocks: [
        "removes the blocker from the largest tracked MCP directory PR",
        "turns Glama proof into directory-discovery reach",
      ],
      external_effects: ["pushes only the owned punkpeye PR branch when approved"],
      why: "This avoids speculative PR edits while preserving the most valuable known directory unlock.",
    }),
    queueItem(6, {
      action: "Create PostHog dashboard shell and read aggregate funnel/direct refs/share/community loops",
      status: "owner_held_credentials",
      owner_decision: "Supply PostHog credentials and approve dashboard/query helpers if measurement should go live.",
      command: `${action4.command}\n\n${action5.command}`,
      guard: `${action4.guard || "Requires PostHog approval"}; ${action5.guard || "Requires PostHog query approval"}`,
      depends_on: [
        "step 3 controlled install receipt proof",
        "PostHog host/project/environment IDs and personal API key from owner",
      ],
      unlocks: [
        "surface-ranked attributed first runs",
        "direct gh-* directory/listing install ref ranking",
        "owned share propagation evidence",
        "Reddit community participation evidence",
        "activation evidence for deciding which channels deserve follow-up",
      ],
      external_effects: [
        "PostHog dashboard shell/setup tile creation",
        "read-only aggregate PostHog Query API calls",
      ],
      why: "The funnel, direct-ref, share-loop, and Reddit community readouts distinguish real growth from copy clicks before scaling promotion.",
    }),
    queueItem(7, {
      action: "Launch social copy manually",
      status: receipts.social_launch_receipt_recorded ? "completed" : "owner_held_after_live_verification",
      owner_decision: "Owner chooses exact platform, posts manually, then records the live URL.",
      command: socialLaunchCommand,
      guard: action6.guard || "No automated posting; owner chooses exact target",
      depends_on: [
        "step 2 verified live attribution, PostHog proxy, and LLM discovery",
        "owner-selected HN/X/Reddit target and exact copy",
        "published URL after the owner-approved manual post exists",
      ],
      unlocks: [
        "attributed top-of-funnel traffic",
        "source comparison against directory traffic",
        "Social launch receipts row for docs/ops/growth-report.md",
        "owner-reviewable reply packet for the selected surface",
      ],
      external_effects: action6.external_effects || ["owner manually posts selected HN/X/Reddit copy outside automation"],
      why: "Social launch should happen only after the measurement surface is live and inspectable.",
    }),
    queueItem(8, {
      action: "Review directory follow-up by priority",
      status: "ready_local_packet_owner_approval_for_any_reply",
      owner_decision: "Use the generated packet to choose exact maintainer replies or hold.",
      command: `scripts/check-directory-pr-state.sh ${brief.growth_report || "docs/ops/growth-report.md"}\nnode scripts/prepare-directory-priority-report.js --markdown ${brief.growth_report || "docs/ops/growth-report.md"}\nnode scripts/prepare-directory-surface-refs.js --markdown ${brief.growth_report || "docs/ops/growth-report.md"}\nnode scripts/prepare-directory-followup-kit.js --markdown --actionable ${brief.growth_report || "docs/ops/growth-report.md"}`,
      guard: "Read-only packet; no comments, edits, or PR pushes without target-specific owner approval",
      depends_on: [
        "step 2 verified live attribution and LLM discovery for any claim about live install copy or agent-discovery files",
        "maintainer request, registry proof need, failing-check fix, or owner-approved target",
      ],
      unlocks: [
        "focused attention on high-reach open listings",
        "avoids low-signal bump comments",
      ],
      external_effects: ["read-only local packets; no comments or PR edits"],
      why: "Directory follow-up scales only when it is prioritized by reach and actual blocker status.",
    }),
  ];
}

function buildDecisionQueue(tag) {
  const brief = readApprovalBrief(tag);
  const queue = buildQueue(brief, tag);
  const validations = [
    ...validationFailures(brief),
    ...queueValidationFailures(queue),
  ];
  return {
    schema_version: 1,
    repo: brief.repo,
    tag,
    server_name: brief.server_name,
    server_version: brief.server_version,
    git: brief.git,
    approved_head: brief.git.head_full || "",
    growth_report: brief.growth_report,
    ready_for_owner_review: brief.ready_for_owner_review,
    local_checks: brief.local_checks,
    validation_failures: validations,
    top_decision: queue.find((item) => item.status !== "completed") || queue[0],
    critical_path: queue,
    known_holds: brief.known_holds,
    forbidden_without_approval: brief.forbidden_without_approval,
  };
}

function printCheck(decisionQueue) {
  if (decisionQueue.validation_failures.length) {
    console.log("GROWTH DECISION QUEUE: FAIL");
    for (const failure of decisionQueue.validation_failures) {
      console.log(`  FAIL: ${failure}`);
    }
    process.exit(1);
  }
  console.log("GROWTH DECISION QUEUE: PASS");
  console.log(`  repo: ${decisionQueue.repo}`);
  console.log(`  tag: ${decisionQueue.tag}`);
  console.log(`  branch: ${decisionQueue.git.branch} @ ${decisionQueue.git.head}`);
  console.log(`  approved head: ${decisionQueue.approved_head}`);
  console.log(`  ahead/behind: ${decisionQueue.git.ahead}/${decisionQueue.git.behind}`);
  console.log(`  working tree: ${decisionQueue.git.clean ? "clean" : "dirty"}`);
  console.log(`  ready for owner review: ${decisionQueue.ready_for_owner_review ? "yes" : "not yet"}`);
  console.log(`  critical path items: ${decisionQueue.critical_path.length}`);
  console.log(`  top decision: ${decisionQueue.top_decision.action}`);
  console.log(`  top command: ${shortCommand(decisionQueue.top_decision.command)}`);
}

function printMarkdown(decisionQueue) {
  console.log("# Growth Decision Queue");
  console.log();
  console.log("READ ONLY: this queue does not push, upload, dispatch workflows, publish registry metadata, post, comment, submit, pay, or use account identity.");
  console.log();
  console.log("## Current State");
  console.log();
  console.log(`- Repo: \`${decisionQueue.repo}\``);
  console.log(`- Target tag: \`${decisionQueue.tag}\``);
  console.log(`- Registry server/version: \`${decisionQueue.server_name}\` / \`${decisionQueue.server_version}\``);
  console.log(`- Branch: \`${decisionQueue.git.branch}\` at \`${decisionQueue.git.head}\``);
  console.log(`- Approved HEAD: \`${decisionQueue.approved_head}\``);
  console.log(`- Base: \`${decisionQueue.git.base_ref}\`, ahead/behind: \`${decisionQueue.git.ahead}/${decisionQueue.git.behind}\``);
  console.log(`- Working tree: ${decisionQueue.git.clean ? "clean" : "dirty"}`);
  console.log(`- Ready for owner review: ${decisionQueue.ready_for_owner_review ? "yes" : "not yet"}`);
  if (decisionQueue.growth_report) {
    console.log(`- Growth report: \`${decisionQueue.growth_report}\``);
  }
  console.log();
  console.log("## Top Owner Decision");
  console.log();
  console.log(`- Decision: ${decisionQueue.top_decision.owner_decision}`);
  console.log(`- Action: ${decisionQueue.top_decision.action}`);
  console.log(`- Status: \`${decisionQueue.top_decision.status}\``);
  console.log(`- Guard: ${decisionQueue.top_decision.guard}`);
  if (decisionQueue.top_decision.expected_head) {
    console.log(`- Expected hosted verifier HEAD: \`${decisionQueue.top_decision.expected_head}\``);
  }
  if (decisionQueue.top_decision.approval_scope.length) {
    console.log("- Approval scope:");
    for (const item of decisionQueue.top_decision.approval_scope) {
      console.log(`  - ${item}`);
    }
  }
  console.log();
  console.log("```bash");
  console.log(decisionQueue.top_decision.command);
  console.log("```");
  console.log();
  console.log("## Critical Path");
  console.log();
  for (const item of decisionQueue.critical_path) {
    console.log(`${item.rank}. ${item.action}`);
    console.log();
    console.log(`Status: \`${item.status}\``);
    console.log(`Owner decision: ${item.owner_decision}`);
    console.log(`Guard: ${item.guard}`);
    if (item.expected_head) {
      console.log(`Expected hosted verifier HEAD: \`${item.expected_head}\``);
    }
    console.log(`Why: ${item.why}`);
    console.log();
    console.log("Depends on:");
    for (const dependency of item.depends_on) {
      console.log(`- ${dependency}`);
    }
    console.log();
    console.log("Unlocks:");
    for (const unlock of item.unlocks) {
      console.log(`- ${unlock}`);
    }
    console.log();
    console.log("```bash");
    console.log(item.command);
    console.log("```");
    console.log();
  }
  console.log("## Known Holds");
  console.log();
  for (const hold of decisionQueue.known_holds) {
    console.log(`- ${hold}`);
  }
  console.log();
  console.log("## Forbidden Without Fresh Owner Approval");
  console.log();
  for (const item of decisionQueue.forbidden_without_approval) {
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
const decisionQueue = buildDecisionQueue(tag);

if (mode === "--json") {
  console.log(JSON.stringify(decisionQueue, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(decisionQueue);
} else {
  printCheck(decisionQueue);
}
