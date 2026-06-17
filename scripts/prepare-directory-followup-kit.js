#!/usr/bin/env node
// Prepare owner-reviewable directory/listing follow-up notes.
//
// This is local-only. It reads Markdown/stdin, extracts GitHub PR URLs, derives
// stable attribution refs and registry facts, then prints notes the owner can
// review before any maintainer reply or listing update. It never queries GitHub,
// posts comments, edits PRs, pushes branches, submits forms, pays, or uses
// account identity.

const fs = require("fs");

const HOME_URL = "https://accint.xyz/";
const URL_RE = /https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/pull\/([0-9]+)/g;
const VALUE_RE = /^[A-Za-z0-9._:/?+,-]{1,96}$/;

function usage() {
  console.error(`usage: node scripts/prepare-directory-followup-kit.js [--check|--markdown|--json] <file-or-> [file-or-...]

Examples:
  node scripts/prepare-directory-followup-kit.js --check /path/to/NIGHT-REPORT.md
  node scripts/prepare-directory-followup-kit.js --markdown /path/to/NIGHT-REPORT.md
  sed -n '/^| # | List |/,/^$/p' report.md | node scripts/prepare-directory-followup-kit.js --json -

Modes:
  --check     validate the extracted follow-up kit and print a compact summary
  --markdown  print owner-reviewable maintainer notes
  --json      print structured rows

Output is review material only. Do not post, comment, submit, push, or edit a
directory/listing from this output without explicit owner approval for that
exact target.
`);
}

function die(message, code = 1) {
  console.error(`DIRECTORY FOLLOW-UP KIT: ${message}`);
  process.exit(code);
}

function read(file) {
  if (file === "-") {
    return fs.readFileSync(0, "utf8");
  }
  if (!fs.existsSync(file)) {
    die(`input not found: ${file}`, 2);
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
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

function registryFacts() {
  const server = readJson("server.json");
  const name = server.name;
  const version = server.version;
  if (!name || !version) {
    die("server.json must contain name and version");
  }
  const packages = Array.isArray(server.packages) ? server.packages : [];
  const mcpb = packages.filter((pkg) => pkg && pkg.registryType === "mcpb");
  if (mcpb.length === 0) {
    die("server.json must contain at least one MCPB package");
  }
  return {
    name,
    version,
    endpoint: `https://registry.modelcontextprotocol.io/v0.1/servers/${encodeURIComponent(name)}/versions/latest`,
    package_count: mcpb.length,
    platforms: mcpb.map((pkg) => String(pkg.identifier || "").split("/").pop()).filter(Boolean),
  };
}

function validateSource(source, url) {
  for (const part of source.split("&")) {
    const [key, value] = part.split("=");
    if (!key || !value || !VALUE_RE.test(value)) {
      die(`${url}: invalid source part ${part}`);
    }
  }
  if (source.length > 160) {
    die(`${url}: source envelope exceeds installer cap`);
  }
}

function maintainerNote(row, registry) {
  return [
    "Quick reviewer context for this AccInt listing:",
    "",
    `- Official MCP Registry metadata: ${registry.endpoint}`,
    `- Registry name/version: \`${registry.name}\` / \`${registry.version}\``,
    `- Package form: MCPB local stdio server packages (${registry.package_count} platform bundles) plus the one-line installer for host wiring`,
    "- Source boundary: Apache-2.0 public installer/docs/plugins/registry metadata; proprietary local engine binary under EULA; engine source private",
    "- Data posture: local substrate, no cloud memory account; anonymous event-name telemetry is opt-out and excludes prompts, files, memory, and Work Model data",
    `- Attributed landing URL for this listing if useful: ${row.landing_url}`,
    "",
    "No action requested unless this helps review; I am keeping this factual so the listing can use the right package/discovery link and source-boundary wording.",
  ].join("\n");
}

function extractRows(text, registry) {
  const byUrl = new Map();
  const usedRefs = new Set();

  for (const line of text.split(/\r?\n/)) {
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
      validateSource(source, url);
      const row = {
        target: rowLabel(cells, owner, repo, url),
        repo: `${owner}/${repo}`,
        number,
        pr_url: url,
        section: rowSection(cells, url),
        ref,
        source,
        landing_url: landingUrl(source),
      };
      row.note = maintainerNote(row, registry);
      byUrl.set(url, row);
    }
  }

  return [...byUrl.values()];
}

function printMarkdown(rows, registry) {
  console.log("# Directory Follow-up Kit");
  console.log();
  console.log("READ ONLY: this output is owner-review material. Do not post, comment, submit, push, or edit any directory/listing unless the owner explicitly approves that exact target.");
  console.log();
  console.log("## Registry Proof");
  console.log();
  console.log(`- Registry: \`${registry.name}\``);
  console.log(`- Version: \`${registry.version}\``);
  console.log(`- Latest endpoint: ${registry.endpoint}`);
  console.log(`- MCPB packages: ${registry.package_count}`);
  console.log();
  for (const row of rows) {
    console.log(`## ${row.target}`);
    console.log();
    console.log(`- PR: ${row.pr_url}`);
    console.log(`- Ref: \`${row.ref}\``);
    console.log(`- Source: \`${row.source}\``);
    console.log(`- Attributed landing URL: ${row.landing_url}`);
    console.log();
    console.log("Maintainer note draft:");
    console.log();
    console.log("```text");
    console.log(row.note);
    console.log("```");
    console.log();
  }
}

function printCheck(rows, registry) {
  console.log("DIRECTORY FOLLOW-UP KIT: PASS");
  console.log(`  registry: ${registry.name}`);
  console.log(`  version: ${registry.version}`);
  console.log(`  MCPB packages: ${registry.package_count}`);
  console.log(`  PR URLs: ${rows.length}`);
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

const registry = registryFacts();
const text = args.map(read).join("\n");
const rows = extractRows(text, registry);
if (!rows.length) {
  die("no GitHub PR URLs found");
}

if (mode === "--json") {
  console.log(JSON.stringify({ schema_version: 1, registry, rows }, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(rows, registry);
} else {
  printCheck(rows, registry);
}
