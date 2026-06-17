#!/usr/bin/env node
// Rank tracked directory/listing PRs by expected growth leverage.
//
// This is read-only. It extracts GitHub PR URLs from a Markdown report, queries
// GitHub for live PR/repo metadata, and prints a prioritized owner-review queue.
// It never comments, edits, pushes, submits, dispatches workflows, pays, or uses
// account identity beyond read-only `gh` API access.

const childProcess = require("child_process");
const fs = require("fs");

const URL_RE = /https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/pull\/([0-9]+)/g;

function usage() {
  console.error(`usage: node scripts/prepare-directory-priority-report.js [--check|--markdown|--json] <file-or-> [file-or-...]

Examples:
  node scripts/prepare-directory-priority-report.js --check docs/ops/growth-report.md
  node scripts/prepare-directory-priority-report.js --markdown docs/ops/growth-report.md
  sed -n '/^| # | List |/,/^$/p' docs/ops/growth-report.md | node scripts/prepare-directory-priority-report.js --json -

Output is owner-review material only. Do not post, comment, submit, push, edit a
PR, or use account identity without explicit owner approval for that exact target.
`);
}

function die(message, code = 1) {
  console.error(`DIRECTORY PRIORITY REPORT: ${message}`);
  process.exit(code);
}

function run(command, args, optional = false) {
  const completed = childProcess.spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (completed.status !== 0) {
    if (optional) {
      return null;
    }
    const detail = (completed.stderr || completed.stdout || "").trim();
    die(`${command} ${args.join(" ")} failed${detail ? `: ${detail}` : ""}`, completed.status || 1);
  }
  return completed.stdout.trim();
}

function readInput(arg) {
  if (arg === "-") {
    return fs.readFileSync(0, "utf8");
  }
  if (!fs.existsSync(arg)) {
    die(`input not found: ${arg}`, 2);
  }
  return fs.readFileSync(arg, "utf8");
}

function splitMarkdownRow(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("|") || !trimmed.endsWith("|")) {
    return [];
  }
  return trimmed
    .slice(1, -1)
    .split("|")
    .map((cell) => cell.trim());
}

function clean(value) {
  return String(value || "")
    .replace(/`/g, "")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function extractRows(text) {
  const rows = [];
  const seen = new Set();
  for (const line of text.split(/\r?\n/)) {
    const matches = [...line.matchAll(URL_RE)];
    if (!matches.length) {
      continue;
    }
    const cells = splitMarkdownRow(line);
    for (const match of matches) {
      const [, owner, repo, numberText] = match;
      const number = Number(numberText);
      const prUrl = `https://github.com/${owner}/${repo}/pull/${number}`;
      if (seen.has(prUrl)) {
        continue;
      }
      seen.add(prUrl);
      rows.push({
        repo: `${owner}/${repo}`,
        number,
        pr_url: prUrl,
        area: clean(cells[2] || ""),
        state_at_refresh: clean(cells[3] || ""),
        note: clean(cells[6] || ""),
      });
    }
  }
  return rows;
}

function ghJson(args, optional = false, input = null) {
  const completed = childProcess.spawnSync("gh", args, {
    encoding: "utf8",
    input: input || undefined,
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (completed.status !== 0) {
    if (optional) {
      return null;
    }
    const detail = (completed.stderr || completed.stdout || "").trim();
    const safeArgs = args.map((arg) => (String(arg).length > 180 ? `${String(arg).slice(0, 180)}...` : arg));
    die(`gh ${safeArgs.join(" ")} failed${detail ? `: ${detail}` : ""}`, completed.status || 1);
  }
  const stdout = completed.stdout.trim();
  if (stdout === null || stdout === "") {
    return null;
  }
  try {
    return JSON.parse(stdout);
  } catch (err) {
    if (optional) {
      return null;
    }
    die(`could not parse gh JSON for ${args.join(" ")}: ${err.message}`);
  }
}

function aliasFor(index) {
  return `r${index}`;
}

function gqlString(value) {
  return JSON.stringify(String(value || ""));
}

function fetchLiveRows(rows) {
  const results = new Array(rows.length);
  const batchSize = 18;
  for (let start = 0; start < rows.length; start += batchSize) {
    const batch = rows.slice(start, start + batchSize);
    const parts = batch.map((row, localIndex) => {
      const index = start + localIndex;
      const [owner, repo] = row.repo.split("/");
      return `${aliasFor(index)}: repository(owner: ${gqlString(owner)}, name: ${gqlString(repo)}) {
      nameWithOwner
      url
      description
      stargazerCount
      pullRequest(number: ${row.number}) {
        title
        url
        state
        isDraft
        mergeStateStatus
        reviewDecision
        updatedAt
      }
    }`;
    });
    const query = `query AccIntDirectoryPriority${start} {\n${parts.join("\n")}\n}`;
    const data = ghJson(["api", "graphql", "-f", `query=${query}`]) || {};
    const root = data.data || {};
    batch.forEach((row, localIndex) => {
      const index = start + localIndex;
      const repo = root[aliasFor(index)] || {};
      const pr = repo.pullRequest || {};
      results[index] = {
      repo: {
        repo: row.repo,
        stars: Number(repo.stargazerCount || 0),
        description: repo.description || "",
        url: repo.url || `https://github.com/${row.repo}`,
      },
      pr: {
        title: pr.title || "",
        state: pr.state || row.state_at_refresh || "",
        isDraft: Boolean(pr.isDraft),
        mergeStateStatus: pr.mergeStateStatus || "",
        reviewDecision: pr.reviewDecision || "",
        updatedAt: pr.updatedAt || "",
        url: pr.url || row.pr_url,
      },
      };
    });
  }
  return results;
}

function areaBoost(area) {
  const value = area.toLowerCase();
  if (value.includes("mcp")) return 12;
  if (value.includes("claude") || value.includes("codex") || value.includes("opencode")) return 9;
  if (value.includes("memory") || value.includes("context")) return 8;
  if (value.includes("skill")) return 6;
  if (value.includes("agent")) return 5;
  return 3;
}

function reachScore(stars) {
  return Math.round(Math.log10(Math.max(1, stars) + 1) * 20);
}

function recommendation(row, live, repo) {
  const state = String(live.state || row.state_at_refresh || "").toUpperCase();
  const note = `${row.note} ${row.area}`.toLowerCase();
  const merge = String(live.mergeStateStatus || "").toUpperCase();
  const review = String(live.reviewDecision || "").toUpperCase();

  if (state === "MERGED") {
    return {
      bucket: "banked",
      score: 0,
      action: "Banked listing. Monitor attribution and do not bump.",
      reason: "merged",
    };
  }
  if (state === "CLOSED") {
    return {
      bucket: "closed",
      score: 0,
      action: "Do not retry unless policy or source-boundary fit changes.",
      reason: "closed unmerged",
    };
  }

  let score = reachScore(repo.stars) + areaBoost(row.area);
  const reasons = [];
  let action = "Hold for maintainer signal; do not bump.";

  if (note.includes("glama")) {
    score += 35;
    reasons.push("blocked on Glama prerequisite");
    action = "Highest-leverage prerequisite: get a real Glama listing/badge, then update the owned PR branch only with approval.";
  }
  if (note.includes("failing checks")) {
    score += 20;
    reasons.push("failing checks");
    action = "Inspect failing checks and prepare an owner-approved fix path before any reply.";
  }
  if (merge === "BLOCKED" || review === "REVIEW_REQUIRED") {
    score += 15;
    reasons.push("review/merge blocked");
    action = "Prepare a concise owner-approved clarification only if maintainer policy or review asks for it.";
  }
  if (merge === "UNSTABLE") {
    score += 5;
    reasons.push("unstable merge state");
  }
  if (!reasons.length) {
    reasons.push("open clean");
  }

  return {
    bucket: score >= 85 ? "priority" : "watch",
    score,
    action,
    reason: reasons.join("; "),
  };
}

function build(rows) {
  const liveRows = fetchLiveRows(rows);
  const out = [];
  rows.forEach((row, index) => {
    const repo = liveRows[index].repo;
    const live = liveRows[index].pr;
    const rec = recommendation(row, live, repo);
    out.push({
      index: index + 1,
      repo: row.repo,
      pr_number: row.number,
      pr_url: row.pr_url,
      title: live.title || "",
      area: row.area,
      note: row.note,
      state: live.state || row.state_at_refresh || "",
      merge_state: live.mergeStateStatus || "",
      review: live.reviewDecision || "",
      checks: row.note.toLowerCase().includes("failing checks") ? "reported failing" : "see PR audit",
      updated_at: live.updatedAt || "",
      stars: repo.stars,
      score: rec.score,
      bucket: rec.bucket,
      reason: rec.reason,
      action: rec.action,
    });
  });
  return out.sort((a, b) => b.score - a.score || b.stars - a.stars || a.pr_url.localeCompare(b.pr_url));
}

function escapeMd(value) {
  return String(value || "").replace(/\|/g, "\\|").replace(/\n/g, " ").trim();
}

function printMarkdown(rows) {
  console.log("# Directory Priority Report");
  console.log();
  console.log("READ ONLY: owner-review material only. Do not post, comment, edit PRs, push, submit, pay, or use account identity without exact owner approval.");
  console.log();
  console.log("| Rank | Score | Stars | PR | State | Checks | Reason | Owner-review next action |");
  console.log("|---:|---:|---:|---|---|---|---|---|");
  rows.forEach((row, rank) => {
    console.log(
      `| ${rank + 1} | ${row.score} | ${row.stars} | [${escapeMd(row.repo)}#${row.pr_number}](${row.pr_url}) | ${escapeMd(row.state)} | ${escapeMd(row.checks)} | ${escapeMd(row.reason)} | ${escapeMd(row.action)} |`
    );
  });
}

function printCheck(rows) {
  const open = rows.filter((row) => row.state === "OPEN").length;
  const merged = rows.filter((row) => row.state === "MERGED").length;
  const closed = rows.filter((row) => row.state === "CLOSED").length;
  const priority = rows.filter((row) => row.bucket === "priority").length;
  console.log("DIRECTORY PRIORITY REPORT: PASS");
  console.log(`  PR URLs: ${rows.length}`);
  console.log(`  open: ${open}`);
  console.log(`  merged: ${merged}`);
  console.log(`  closed: ${closed}`);
  console.log(`  priority items: ${priority}`);
  rows.slice(0, 5).forEach((row, index) => {
    console.log(`  ${index + 1}. score=${row.score} stars=${row.stars} ${row.repo}#${row.pr_number}: ${row.reason}`);
  });
}

let mode = "--check";
const args = process.argv.slice(2);
if (args[0] === "-h" || args[0] === "--help") {
  usage();
  process.exit(0);
}
if (["--check", "--markdown", "--json"].includes(args[0])) {
  mode = args.shift();
}
if (args.length === 0) {
  usage();
  process.exit(2);
}
if (!run("gh", ["--version"], true)) {
  die("gh CLI is required for read-only directory priority checks", 2);
}

const text = args.map(readInput).join("\n");
const extracted = extractRows(text);
if (!extracted.length) {
  die("no GitHub PR URLs found");
}

const rows = build(extracted);
if (mode === "--json") {
  console.log(JSON.stringify({ schema_version: 1, rows }, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(rows);
} else {
  printCheck(rows);
}
