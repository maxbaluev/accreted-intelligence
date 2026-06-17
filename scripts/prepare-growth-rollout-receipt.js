#!/usr/bin/env node
// Print read-only growth-report receipt rows for an approved public rollout.
//
// This helper does not push, dispatch workflows, query GitHub, edit files, post,
// comment, submit, pay, or use account identity. It only turns the current local
// HEAD and an optional hosted verifier run URL into copyable markdown receipts.

const childProcess = require("child_process");
const fs = require("fs");

const REPO = process.env.ACC_GROWTH_REPO || "maxbaluev/accreted-intelligence";
const REMOTE = process.env.ACC_GROWTH_REMOTE || "origin";
const GROWTH_REPORT = process.env.ACC_GROWTH_REPORT || "docs/ops/growth-report.md";
const HOSTED_RUN_PLACEHOLDER = "<hosted-live-verifier-run-url>";
const RECEIPT_TABLE_HEADER = "| Date | Surface | Action | Receipt | State |";

function usage() {
  console.error(`usage: node scripts/prepare-growth-rollout-receipt.js [--check|--markdown|--json] [tag] [hosted-run-url]

Examples:
  node scripts/prepare-growth-rollout-receipt.js --check v0.1.6
  node scripts/prepare-growth-rollout-receipt.js --markdown v0.1.6 https://github.com/maxbaluev/accreted-intelligence/actions/runs/27691022310

Output is receipt material only. Append rows to docs/ops/growth-report.md only
after the owner-approved push and hosted verifier run actually exist.
`);
}

function die(message, code = 1) {
  console.error(`GROWTH ROLLOUT RECEIPT: ${message}`);
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
  return {
    branch,
    head: run("git", ["rev-parse", "--short", "HEAD"]),
    head_full: run("git", ["rev-parse", "HEAD"]),
    clean: run("git", ["status", "--porcelain"], { optional: true }).length === 0,
  };
}

function hostedRunUrl(input) {
  const url = input || process.env.ACC_HOSTED_RUN_URL || HOSTED_RUN_PLACEHOLDER;
  if (url !== HOSTED_RUN_PLACEHOLDER && !/^https:\/\/github\.com\/[^/\s]+\/[^/\s]+\/actions\/runs\/[0-9]+$/i.test(url)) {
    die(`hosted run URL must be a GitHub Actions run URL or ${HOSTED_RUN_PLACEHOLDER}: ${url}`);
  }
  return url;
}

function markdownValue(value) {
  return value === HOSTED_RUN_PLACEHOLDER ? `\`${value}\`` : value;
}

function validateReport(report) {
  if (!report.includes("## External rollout receipts")) {
    die(`${GROWTH_REPORT}: missing External rollout receipts section`);
  }
  if (!report.includes(RECEIPT_TABLE_HEADER) || !report.includes("|---|---|---|---|---|")) {
    die(`${GROWTH_REPORT}: missing external rollout receipts table`);
  }
}

function buildReceipt(tag, runUrl) {
  const server = readJson("server.json");
  const state = gitState();
  const date = (process.env.ACC_RECEIPT_DATE || new Date().toISOString().slice(0, 10));
  const expectedHead = state.head_full;
  return {
    schema_version: 1,
    repo: REPO,
    remote: REMOTE,
    branch: state.branch,
    tag,
    server_name: server.name || "",
    server_version: server.version || "",
    approved_head: expectedHead,
    short_head: state.head,
    working_tree_clean: state.clean,
    hosted_run_url: runUrl,
    growth_report: GROWTH_REPORT,
    rows: [
      {
        date,
        surface: "Public repo",
        action: `ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh ${tag}`,
        receipt: `\`${expectedHead}\` pushed to \`${REMOTE}/${state.branch}\``,
        state: `Owner-approved rollout for exact HEAD; hosted verifier dispatched with \`expected_head=${expectedHead}\`.`,
      },
      {
        date,
        surface: "Hosted live verifier",
        action: "live-site-attribution.yml",
        receipt: markdownValue(runUrl),
        state: `Record after the run passes live attribution, PostHog proxy, and LLM discovery checks for \`expected_head=${expectedHead}\`.`,
      },
    ],
  };
}

function markdownRow(row) {
  return `| ${row.date} | ${row.surface} | \`${row.action}\` | ${row.receipt} | ${row.state} |`;
}

function validateReceipt(receipt) {
  if (!/^[0-9a-f]{40}$/.test(receipt.approved_head)) {
    die("approved_head must be the full 40-character git SHA");
  }
  if (!receipt.rows.some((row) => row.state.includes(`expected_head=${receipt.approved_head}`))) {
    die("receipt rows must bind the hosted verifier to expected_head");
  }
  if (!receipt.rows.some((row) => row.surface === "Hosted live verifier")) {
    die("receipt packet must include a hosted live verifier row");
  }
  validateReport(readText(GROWTH_REPORT));
}

function printCheck(receipt) {
  validateReceipt(receipt);
  console.log("GROWTH ROLLOUT RECEIPT: PASS");
  console.log(`  repo: ${receipt.repo}`);
  console.log(`  tag: ${receipt.tag}`);
  console.log(`  branch: ${receipt.branch} @ ${receipt.short_head}`);
  console.log(`  approved head: ${receipt.approved_head}`);
  console.log(`  hosted run URL: ${receipt.hosted_run_url}`);
  console.log(`  rows: ${receipt.rows.length}`);
}

function printMarkdown(receipt) {
  validateReceipt(receipt);
  console.log("# Growth Rollout Receipt Packet");
  console.log();
  console.log("READ ONLY: append these rows only after the owner-approved public push and hosted verifier run actually exist. This packet does not edit files, push, dispatch workflows, post, submit, pay, or use account identity.");
  console.log();
  console.log(`- Repo: \`${receipt.repo}\``);
  console.log(`- Tag: \`${receipt.tag}\``);
  console.log(`- Branch: \`${receipt.branch}\` at \`${receipt.short_head}\``);
  console.log(`- Approved HEAD: \`${receipt.approved_head}\``);
  console.log(`- Hosted run URL: ${markdownValue(receipt.hosted_run_url)}`);
  if (receipt.hosted_run_url === HOSTED_RUN_PLACEHOLDER) {
    console.log("- Hosted run URL note: rerun with the actual GitHub Actions run URL as the second argument before appending the hosted verifier row.");
  }
  console.log(`- Growth report: \`${receipt.growth_report}\``);
  console.log();
  console.log("Append to `## External rollout receipts` in `docs/ops/growth-report.md` after verification:");
  console.log();
  console.log("```markdown");
  for (const row of receipt.rows) {
    console.log(markdownRow(row));
  }
  console.log("```");
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
const receipt = buildReceipt(tag, hostedRunUrl(args[1]));

if (mode === "--json") {
  validateReceipt(receipt);
  console.log(JSON.stringify(receipt, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(receipt);
} else {
  printCheck(receipt);
}
