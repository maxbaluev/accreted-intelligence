#!/usr/bin/env node
// Prepare owner-reviewable social launch packets from the checked launch kit.
//
// This is local-only. It reads docs/ops/social-launch-kit.md and
// docs/ops/growth-surfaces.json, validates attribution/copy constraints, and
// prints review material. It never opens posting URLs, posts, comments, DMs,
// submits forms, pays, or uses account identity.

const fs = require("fs");
const path = require("path");

const MANIFEST_PATH = path.join("docs", "ops", "growth-surfaces.json");
const KIT_PATH = path.join("docs", "ops", "social-launch-kit.md");
const REPO_URL = "https://github.com/maxbaluev/accreted-intelligence";
const VALUE_RE = /^[A-Za-z0-9._:/?+,-]{1,96}$/;
const FORBIDDEN_CLAIMS = ["fully open source", "open-source engine", "public memory implementation"];

function usage() {
  console.error(`usage: node scripts/prepare-social-launch-packet.js [--check|--markdown|--json]

Modes:
  --check     validate the social launch packet and print a compact summary
  --markdown  print owner-reviewable post packets
  --json      print structured packet data

Output is review material only. Do not post, submit, comment, DM, pay, or use
an account identity from this output without explicit owner approval for that
exact target.
`);
}

function die(message, code = 1) {
  console.error(`SOCIAL LAUNCH PACKET: ${message}`);
  process.exit(code);
}

function read(file) {
  if (!fs.existsSync(file)) {
    die(`missing ${file}`);
  }
  return fs.readFileSync(file, "utf8");
}

function loadManifest() {
  let manifest;
  try {
    manifest = JSON.parse(read(MANIFEST_PATH));
  } catch (err) {
    die(`${MANIFEST_PATH}: ${err.message}`);
  }
  if (manifest.schema !== 1) {
    die(`${MANIFEST_PATH}: expected schema 1`);
  }
  if (!manifest.base_urls || !Array.isArray(manifest.surfaces)) {
    die(`${MANIFEST_PATH}: missing base_urls or surfaces`);
  }
  return manifest;
}

function sourceQuery(surface) {
  return Object.entries(surface.source)
    .map(([key, value]) => `${key}=${value}`)
    .join("&");
}

function landingUrl(manifest, surface) {
  const base = manifest.base_urls[surface.landing];
  if (!base) {
    die(`${surface.id}: unknown landing ${surface.landing}`);
  }
  return `${base}${base.includes("?") ? "&" : "?"}${sourceQuery(surface)}`;
}

function posixSnippet(manifest, surface) {
  return `curl -fsSL ${manifest.base_urls.posix_installer} | ACC_INSTALL_REF=${surface.id} ACC_INSTALL_SOURCE='${sourceQuery(surface)}' sh`;
}

function powershellSnippet(manifest, surface) {
  return `$env:ACC_INSTALL_REF='${surface.id}'; $env:ACC_INSTALL_SOURCE='${sourceQuery(surface)}'; irm ${manifest.base_urls.powershell_installer} | iex`;
}

function section(text, heading) {
  const marker = `${heading}\n`;
  const start = text.indexOf(marker);
  if (start === -1) {
    die(`${KIT_PATH}: missing section ${heading}`);
  }
  const bodyStart = start + marker.length;
  const next = text.slice(bodyStart).search(/\n## /);
  return next === -1 ? text.slice(bodyStart) : text.slice(bodyStart, bodyStart + next);
}

function subsection(text, heading) {
  const marker = `${heading}\n`;
  const start = text.indexOf(marker);
  if (start === -1) {
    die(`${KIT_PATH}: missing subsection ${heading}`);
  }
  const bodyStart = start + marker.length;
  const next = text.slice(bodyStart).search(/\n### /);
  return next === -1 ? text.slice(bodyStart) : text.slice(bodyStart, bodyStart + next);
}

function codeBlocks(text) {
  const blocks = [];
  const re = /```([A-Za-z0-9_-]*)\n([\s\S]*?)\n```/g;
  let match;
  while ((match = re.exec(text)) !== null) {
    blocks.push({ lang: match[1], body: match[2].trim() });
  }
  return blocks;
}

function blockAfterLabel(text, label) {
  const labelIndex = text.indexOf(label);
  if (labelIndex === -1) {
    die(`${KIT_PATH}: missing label ${label}`);
  }
  const blocks = codeBlocks(text.slice(labelIndex));
  if (!blocks.length) {
    die(`${KIT_PATH}: missing code block after ${label}`);
  }
  return blocks[0].body;
}

function parseNumberedPosts(text) {
  const intro = text.split("Attributed install reply if useful:")[0];
  const posts = [];
  for (const line of intro.split(/\r?\n/)) {
    const match = line.match(/^([0-9]+)\.\s+(.+)$/);
    if (match) {
      posts.push({ number: Number(match[1]), text: match[0].trim() });
    } else if (line.trim() && posts.length > 0 && !line.trim().endsWith(":")) {
      posts[posts.length - 1].text += `\n${line.trim()}`;
    }
  }
  return posts;
}

function getSurface(manifest, id) {
  const surface = manifest.surfaces.find((item) => item.id === id);
  if (!surface) {
    die(`${MANIFEST_PATH}: missing surface ${id}`);
  }
  return surface;
}

function baseRow(manifest, surface) {
  return {
    id: surface.id,
    label: surface.label || surface.id,
    kind: surface.kind,
    source: sourceQuery(surface),
    landing_url: landingUrl(manifest, surface),
    posix: posixSnippet(manifest, surface),
    powershell: powershellSnippet(manifest, surface),
  };
}

function buildPacket(manifest, kitText) {
  const showHn = section(kitText, "## Show HN");
  const xThread = section(kitText, "## X / Twitter thread");
  const reddit = section(kitText, "## Reddit");
  const localLlama = subsection(reddit, "### r/LocalLLaMA");
  const claudeAi = subsection(reddit, "### r/ClaudeAI");
  const chatGptCoding = subsection(reddit, "### r/ChatGPTCoding");

  const rows = [];
  rows.push({
    ...baseRow(manifest, getSurface(manifest, "hn-show")),
    channel: "Hacker News",
    format: "show_hn",
    title: blockAfterLabel(showHn, "Title:"),
    body: blockAfterLabel(showHn, "Body:"),
    install_reply: blockAfterLabel(showHn, "Optional install line for a first comment:"),
  });

  rows.push({
    ...baseRow(manifest, getSurface(manifest, "x-launch-thread")),
    channel: "X / Twitter",
    format: "thread",
    posts: parseNumberedPosts(xThread),
    install_reply: blockAfterLabel(xThread, "Attributed install reply if useful:"),
  });

  const localBlocks = codeBlocks(localLlama);
  rows.push({
    ...baseRow(manifest, getSurface(manifest, "reddit-localllama")),
    channel: "Reddit",
    subreddit: "r/LocalLLaMA",
    format: "post",
    title: localBlocks[0] ? localBlocks[0].body : "",
    body: localBlocks[1] ? localBlocks[1].body : "",
  });

  rows.push({
    ...baseRow(manifest, getSurface(manifest, "reddit-claudeai")),
    channel: "Reddit",
    subreddit: "r/ClaudeAI",
    format: "reply_or_post",
    body: codeBlocks(claudeAi)[0] ? codeBlocks(claudeAi)[0].body : "",
    install_reply: blockAfterLabel(claudeAi, "Attributed install snippet for a comment if requested:"),
  });

  rows.push({
    ...baseRow(manifest, getSurface(manifest, "reddit-chatgptcoding")),
    channel: "Reddit",
    subreddit: "r/ChatGPTCoding",
    format: "reply_or_post",
    body: codeBlocks(chatGptCoding)[0] ? codeBlocks(chatGptCoding)[0].body : "",
    install_reply: blockAfterLabel(chatGptCoding, "Attributed install snippet for a comment if requested:"),
  });

  return rows;
}

function validateManifest(manifest) {
  for (const surface of manifest.surfaces) {
    if (surface.kind !== "social_launch") {
      continue;
    }
    if (!surface.id || surface.source.ref !== surface.id) {
      die(`${MANIFEST_PATH}: ${surface.id || "<missing>"} source.ref must match id`);
    }
    for (const [key, value] of Object.entries(surface.source || {})) {
      if (!VALUE_RE.test(String(value))) {
        die(`${MANIFEST_PATH}: ${surface.id}: invalid source value ${key}=${value}`);
      }
    }
    if (sourceQuery(surface).length > 160) {
      die(`${MANIFEST_PATH}: ${surface.id}: source envelope exceeds installer cap`);
    }
  }
}

function validatePacket(rows, kitText) {
  if (/https?:\/\/news\.ycombinator\.com\/submit/i.test(kitText) || /https?:\/\/x\.com\/compose/i.test(kitText)) {
    die(`${KIT_PATH}: must not include direct submit/compose URLs`);
  }
  const claimText = kitText
    .replace(/Do not claim:[\s\S]*?## Attribution refs/, "## Attribution refs")
    .toLowerCase();
  for (const phrase of FORBIDDEN_CLAIMS) {
    if (claimText.includes(phrase)) {
      die(`${KIT_PATH}: forbidden overclaim present: ${phrase}`);
    }
  }

  for (const row of rows) {
    if (!row.landing_url.includes(row.source)) {
      die(`${row.id}: landing URL does not include source query`);
    }
    const joined = JSON.stringify(row);
    for (const needle of [row.id, row.source, row.landing_url, REPO_URL]) {
      if (!joined.includes(needle)) {
        die(`${row.id}: packet missing ${needle}`);
      }
    }
  }

  const hn = rows.find((row) => row.id === "hn-show");
  if (!hn.title || hn.title.length > 80) {
    die(`hn-show: title must be present and <= 80 chars; got ${hn.title ? hn.title.length : 0}`);
  }
  if (!hn.body.includes("public Apache-2.0") || !hn.body.includes("proprietary") || !hn.body.includes("private")) {
    die("hn-show: body must state public/proprietary/private boundary");
  }

  const x = rows.find((row) => row.id === "x-launch-thread");
  if (!Array.isArray(x.posts) || x.posts.length < 6) {
    die("x-launch-thread: expected at least 6 numbered posts");
  }
  for (const post of x.posts) {
    if (post.text.length > 280) {
      die(`x-launch-thread: post ${post.number} is ${post.text.length} chars; keep it <= 280`);
    }
    if (/raw\.githubusercontent|ACC_INSTALL_REF|ACC_INSTALL_SOURCE/.test(post.text)) {
      die(`x-launch-thread: post ${post.number} contains a long installer; keep it in install_reply`);
    }
  }
  if (x.install_reply.length > 280) {
    die(`x-launch-thread: install reply is ${x.install_reply.length} chars; keep it <= 280`);
  }

  const redditPost = rows.find((row) => row.id === "reddit-localllama");
  if (!redditPost.title || !redditPost.body) {
    die("reddit-localllama: missing title or body");
  }
  if (!redditPost.body.includes("no cloud memory account") || !redditPost.body.includes("proprietary")) {
    die("reddit-localllama: body must state privacy/source boundary");
  }
}

function printCheck(rows) {
  console.log("SOCIAL LAUNCH PACKET: PASS");
  for (const row of rows) {
    if (row.posts) {
      const longest = row.posts.reduce((max, post) => Math.max(max, post.text.length), 0);
      console.log(`  ${row.id}: ${row.label}, ${row.posts.length} posts, longest=${longest} chars`);
    } else if (row.title) {
      console.log(`  ${row.id}: ${row.label}, title=${row.title.length} chars, body=${row.body.length} chars`);
    } else {
      console.log(`  ${row.id}: ${row.label}, body=${row.body.length} chars`);
    }
  }
}

function printMarkdown(rows) {
  console.log("# Social Launch Packet");
  console.log();
  console.log("READ ONLY: this output is owner-review material. Do not post, submit, comment, DM, pay, or use account identity unless the owner explicitly approves that exact target.");
  console.log();
  console.log("Preflight before any post goes live:");
  console.log();
  console.log("```bash");
  console.log("bash scripts/check-growth-readiness.sh");
  console.log("scripts/check-growth-live-state.sh v<tag>");
  console.log("scripts/check-live-attribution-flow.sh https://accint.xyz");
  console.log("node scripts/check-site-metadata.js");
  console.log("node scripts/check-growth-surfaces.js --check");
  console.log("node scripts/check-social-launch-kit.js --check");
  console.log("node scripts/prepare-social-launch-packet.js --check");
  console.log("```");
  console.log();

  for (const row of rows) {
    console.log(`## ${row.label}`);
    console.log();
    console.log(`- Surface ref: \`${row.id}\``);
    console.log(`- Source: \`${row.source}\``);
    console.log(`- Attributed landing URL: ${row.landing_url}`);
    console.log(`- POSIX install: \`${row.posix}\``);
    console.log(`- PowerShell install: \`${row.powershell}\``);
    console.log();
    if (row.title) {
      console.log("Title:");
      console.log();
      console.log("```text");
      console.log(row.title);
      console.log("```");
      console.log();
    }
    if (row.body) {
      console.log("Body:");
      console.log();
      console.log("```text");
      console.log(row.body);
      console.log("```");
      console.log();
    }
    if (row.posts) {
      console.log("Thread:");
      console.log();
      console.log("```text");
      for (const post of row.posts) {
        console.log(post.text);
        console.log();
      }
      console.log("```");
      console.log();
    }
    if (row.install_reply) {
      console.log("Install reply if requested:");
      console.log();
      console.log("```bash");
      console.log(row.install_reply);
      console.log("```");
      console.log();
    }
  }
}

const mode = process.argv[2] || "--check";
if (mode === "-h" || mode === "--help") {
  usage();
  process.exit(0);
}
if (!["--check", "--markdown", "--json"].includes(mode)) {
  usage();
  process.exit(2);
}

const manifest = loadManifest();
validateManifest(manifest);
const kitText = read(KIT_PATH);
const rows = buildPacket(manifest, kitText);
validatePacket(rows, kitText);

if (mode === "--json") {
  console.log(JSON.stringify({ schema_version: 1, rows }, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(rows);
} else {
  printCheck(rows);
}
