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
      ["node", ["scripts/prepare-directory-followup-kit.js", "--check", GROWTH_REPORT]],
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

function exactActions(tag, branch) {
  return [
    {
      stage: "1",
      name: "Push local growth bundle and dispatch hosted live-site verifier",
      command: `ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh ${tag}`,
      external_effects: ["git push origin main", "gh workflow run live-site-attribution.yml"],
      guard: "Requires ACC_APPROVE_GROWTH_ROLLOUT=1",
    },
    {
      stage: "2",
      name: "Verify after deploy, no mutation",
      command: `scripts/check-growth-live-state.sh ${tag}\nscripts/check-live-attribution-flow.sh https://accint.xyz\nnode scripts/check-site-metadata.js`,
      external_effects: ["read-only public site/GitHub checks"],
      guard: "Read-only",
    },
    {
      stage: "3",
      name: "Controlled live install receipt proof",
      command: `ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh ${tag}`,
      external_effects: ["fetch live installer into temp home", "run attribution-only install stop path"],
      guard: "Requires ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1",
    },
    {
      stage: "4",
      name: "PostHog dashboard shell after owner supplies PostHog env",
      command: "POSTHOG_HOST=https://app.posthog.com POSTHOG_ENVIRONMENT_ID=<environment-id> POSTHOG_PERSONAL_API_KEY=<personal-api-key> ACC_APPROVE_POSTHOG_DASHBOARD=1 scripts/run-approved-posthog-dashboard.sh",
      external_effects: ["PostHog dashboard shell/setup tile creation"],
      guard: "Requires ACC_APPROVE_POSTHOG_DASHBOARD=1 and PostHog credentials",
    },
    {
      stage: "5",
      name: "PostHog aggregate funnel readout after dashboard/control install",
      command: "POSTHOG_HOST=https://us.posthog.com POSTHOG_PROJECT_ID=<project-id> POSTHOG_PERSONAL_API_KEY=<personal-api-key> ACC_APPROVE_POSTHOG_QUERY=1 scripts/run-approved-posthog-funnel-check.sh",
      external_effects: ["read-only aggregate PostHog Query API calls"],
      guard: "Requires ACC_APPROVE_POSTHOG_QUERY=1 and PostHog credentials",
    },
    {
      stage: "6",
      name: "Manual social launch posting",
      command: "node scripts/prepare-social-launch-packet.js --markdown",
      external_effects: ["owner manually posts selected HN/X/Reddit copy outside automation"],
      guard: "No automated posting; owner chooses exact target",
    },
    {
      stage: "7",
      name: "Owner-held Glama submission packet for punkpeye blocker",
      command: `node scripts/prepare-glama-submission-packet.js --markdown ${tag}`,
      external_effects: ["owner may manually submit the Glama listing in a logged-in browser"],
      guard: "Packet is read-only; no automated Glama submission or PR badge update",
    },
  ].map((action) => ({ ...action, branch }));
}

function buildBrief(tag) {
  const server = readJson("server.json");
  const state = gitState();
  const bundle = unpublishedBundle(state);
  const checks = runLocalChecks();
  const actions = exactActions(tag, state.branch);
  const failures = checks.filter((check) => !check.ok);
  return {
    schema_version: 1,
    repo: REPO,
    tag,
    server_name: server.name || "",
    server_version: server.version || "",
    git: state,
    unpublished_bundle: bundle,
    growth_report: GROWTH_REPORT || null,
    local_checks: checks,
    ready_for_owner_review: failures.length === 0 && state.clean && state.behind === "0" && state.ahead !== "0",
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
      "Live custom-domain fetch from this environment can report TLS EOF / snap.pango-cloud.com redirect; use hosted verifier after push.",
      "Glama listing/badge is still required before punkpeye badge branch update; use the Glama packet first, then the badge follow-up guard only after the listing is real.",
      "PostHog dashboard/funnel and social posting require explicit owner approval and credentials/manual posting.",
    ],
  };
}

function printCheck(brief) {
  const failures = brief.local_checks.filter((check) => !check.ok);
  if (failures.length) {
    console.log("GROWTH APPROVAL BRIEF: FAIL");
    failures.forEach((check) => console.log(`  FAIL: ${check.label}`));
    process.exit(1);
  }
  console.log("GROWTH APPROVAL BRIEF: PASS");
  console.log(`  repo: ${brief.repo}`);
  console.log(`  tag: ${brief.tag}`);
  console.log(`  branch: ${brief.git.branch} @ ${brief.git.head}`);
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
