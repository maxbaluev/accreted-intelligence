#!/usr/bin/env node
// Generate stable install-attribution refs from directory/listing PR tables.
// This is local-only: it reads Markdown/stdin and prints refs/snippets without
// querying GitHub, posting comments, submitting PRs, or changing remote state.

const fs = require("fs");
const path = require("path");

const HOME_URL = "https://accint.xyz/";
const POSIX_INSTALLER =
  "https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install";
const POWERSHELL_INSTALLER =
  "https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1";
const URL_RE = /https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/pull\/([0-9]+)/g;
const VALUE_RE = /^[A-Za-z0-9._:/?+,-]{1,96}$/;

function usage() {
  console.error(`usage: node scripts/prepare-directory-surface-refs.js [--check|--markdown|--json] <file-or-> [file-or-...]

Examples:
  node scripts/prepare-directory-surface-refs.js --check report.md
  node scripts/prepare-directory-surface-refs.js --markdown report.md
  sed -n '/^| # | List |/,/^$/p' report.md | node scripts/prepare-directory-surface-refs.js --json -

Modes:
  --check     validate extracted refs and print a compact summary
  --markdown  print an owner-reviewable Markdown table
  --json      print structured rows
`);
}

function die(message, code = 1) {
  console.error(`DIRECTORY SURFACE REFS: ${message}`);
  process.exit(code);
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

function cleanCell(value) {
  return String(value || "")
    .replace(/`/g, "")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function slug(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

function refFor(owner, repo, number, used) {
  const baseMax = 72;
  const base = `gh-${slug(owner)}-${slug(repo)}`.slice(0, baseMax).replace(/-+$/g, "");
  let candidate = base || `gh-pr-${number}`;
  if (used.has(candidate)) {
    const suffix = `-pr${number}`;
    candidate = `${candidate.slice(0, baseMax - suffix.length).replace(/-+$/g, "")}${suffix}`;
  }
  if (used.has(candidate)) {
    die(`duplicate generated ref ${candidate}`);
  }
  used.add(candidate);
  return candidate;
}

function sourceFor(ref, number) {
  return `ref=${ref}&utm_source=github&utm_campaign=directory_pr&entry=pr-${number}`;
}

function landingUrl(source) {
  return `${HOME_URL}?${source}`;
}

function posixSnippet(ref, source) {
  return `curl -fsSL ${POSIX_INSTALLER} | ACC_INSTALL_REF=${ref} ACC_INSTALL_SOURCE='${source}' sh`;
}

function powershellSnippet(ref, source) {
  return `$env:ACC_INSTALL_REF='${ref}'; $env:ACC_INSTALL_SOURCE='${source}'; irm ${POWERSHELL_INSTALLER} | iex`;
}

function rowLabel(cells, owner, repo, url) {
  const urlIndex = cells.findIndex((cell) => cell.includes(url));
  if (urlIndex > 0) {
    const candidates = cells.slice(0, urlIndex).map(cleanCell).filter(Boolean);
    const named = candidates.find((cell) => !/^#?$/.test(cell) && !/^[0-9,.kK]+$/.test(cell));
    if (named) {
      return named;
    }
  }
  return `${owner}/${repo}`;
}

function rowSection(cells, url) {
  const urlIndex = cells.findIndex((cell) => cell.includes(url));
  if (urlIndex > 1) {
    const section = cleanCell(cells[urlIndex - 1]);
    if (section && !/^https?:/.test(section)) {
      return section;
    }
  }
  return "";
}

function extractRows(text) {
  const byUrl = new Map();
  const usedRefs = new Set();
  const lines = text.split(/\r?\n/);

  for (const line of lines) {
    const matches = [...line.matchAll(URL_RE)];
    if (!matches.length) {
      continue;
    }
    const cells = splitMarkdownRow(line);
    for (const match of matches) {
      const [, owner, repo, numberText] = match;
      const number = Number(numberText);
      const url = `https://github.com/${owner}/${repo}/pull/${number}`;
      if (byUrl.has(url)) {
        continue;
      }
      const ref = refFor(owner, repo, number, usedRefs);
      const source = sourceFor(ref, number);
      const row = {
        target: rowLabel(cells, owner, repo, url),
        repo: `${owner}/${repo}`,
        number,
        pr_url: url,
        section: rowSection(cells, url),
        ref,
        source,
        landing_url: landingUrl(source),
        posix: posixSnippet(ref, source),
        powershell: powershellSnippet(ref, source),
      };
      validateRow(row);
      byUrl.set(url, row);
    }
  }

  return [...byUrl.values()];
}

function validateRow(row) {
  if (!/^gh-[a-z0-9][a-z0-9-]{1,95}$/.test(row.ref)) {
    die(`${row.pr_url}: invalid ref ${row.ref}`);
  }
  for (const part of row.source.split("&")) {
    const [key, value] = part.split("=");
    if (!key || !value || !VALUE_RE.test(value)) {
      die(`${row.pr_url}: invalid source part ${part}`);
    }
  }
  if (row.source.length > 160) {
    die(`${row.pr_url}: source envelope exceeds installer cap`);
  }
  if (!row.posix.includes(`ACC_INSTALL_REF=${row.ref}`)) {
    die(`${row.pr_url}: POSIX snippet missing ref`);
  }
  if (!row.powershell.includes(`$env:ACC_INSTALL_REF='${row.ref}'`)) {
    die(`${row.pr_url}: PowerShell snippet missing ref`);
  }
}

function escapeMd(value) {
  return String(value || "").replace(/\|/g, "\\|").replace(/\n/g, " ").trim();
}

function printMarkdown(rows) {
  console.log("| Target | PR | Ref | Attributed landing URL | POSIX install | PowerShell install |");
  console.log("|---|---|---|---|---|---|");
  for (const row of rows) {
    console.log(
      [
        escapeMd(row.target),
        row.pr_url,
        `\`${row.ref}\``,
        `\`${row.landing_url}\``,
        `\`${row.posix}\``,
        `\`${row.powershell}\``,
      ].join(" | ").replace(/^/, "| ") + " |"
    );
  }
}

function printSummary(rows) {
  const byRepo = new Set(rows.map((row) => row.repo));
  console.log("DIRECTORY SURFACE REFS: PASS");
  console.log(`  PR URLs: ${rows.length}`);
  console.log(`  repositories: ${byRepo.size}`);
  console.log(`  refs: ${rows.length}`);
  rows.slice(0, 5).forEach((row) => {
    console.log(`  ${row.ref}: ${row.repo}#${row.number}`);
  });
  if (rows.length > 5) {
    console.log(`  ... ${rows.length - 5} more`);
  }
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
if (!["--check", "--markdown", "--json"].includes(mode) || args.length === 0) {
  usage();
  process.exit(2);
}

const text = args.map(readInput).join("\n");
const rows = extractRows(text);
if (!rows.length) {
  die("no GitHub PR URLs found");
}

if (mode === "--json") {
  console.log(JSON.stringify({ schema_version: 1, rows }, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(rows);
} else {
  printSummary(rows);
}
