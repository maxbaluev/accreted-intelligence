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
  console.error(`usage: node scripts/prepare-social-launch-packet.js [--check|--decision-packet|--reply-packet|--receipt-packet|--markdown|--json] [surface-ref] [published-url]

Modes:
  --check            validate the social launch packet and print a compact summary
  --decision-packet  print the one-page owner target choice packet
  --reply-packet     print owner-reviewable replies for a posted launch surface
  --receipt-packet   print the after-posting receipt row for the growth report
  --markdown         print owner-reviewable post packets
  --json             print structured packet data

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

  for (const row of rows) {
    validateReplyDrafts(row);
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
  console.log("scripts/check-live-llms-discovery.sh https://accint.xyz");
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

function printDecisionPacket(rows) {
  const showHn = rows.find((row) => row.id === "hn-show");
  const localLlama = rows.find((row) => row.id === "reddit-localllama");
  const xThread = rows.find((row) => row.id === "x-launch-thread");
  const claudeAi = rows.find((row) => row.id === "reddit-claudeai");
  const chatGptCoding = rows.find((row) => row.id === "reddit-chatgptcoding");

  console.log("# Social Launch Decision Packet");
  console.log();
  console.log("READ ONLY: owner-review material only. Do not post, submit, comment, DM, pay, open compose forms, or use account identity without explicit owner approval for the exact target.");
  console.log();
  console.log("## Preflight");
  console.log();
  console.log("Run these immediately before any owner-approved post:");
  console.log();
  console.log("```bash");
  console.log("bash scripts/check-growth-readiness.sh");
  console.log("scripts/check-growth-live-state.sh v<tag>");
  console.log("scripts/check-live-attribution-flow.sh https://accint.xyz");
  console.log("scripts/check-live-llms-discovery.sh https://accint.xyz");
  console.log("node scripts/check-site-metadata.js");
  console.log("node scripts/check-growth-surfaces.js --check");
  console.log("node scripts/check-social-launch-kit.js --check");
  console.log("node scripts/prepare-social-launch-packet.js --check");
  console.log("```");
  console.log();
  console.log("## Recommended First Launch");
  console.log();
  console.log("Start with `Show HN` after the live attribution and LLM discovery verifiers pass. It is the broadest standalone technical launch in the checked packet, has a short title, and sends traffic through a single attributed landing URL.");
  console.log();
  console.log(`- Surface ref: \`${showHn.id}\``);
  console.log(`- Attributed landing URL: ${showHn.landing_url}`);
  console.log(`- Title length: ${showHn.title.length} chars`);
  console.log(`- Body length: ${showHn.body.length} chars`);
  console.log();
  console.log("Review full copy:");
  console.log();
  console.log("```bash");
  console.log("node scripts/prepare-social-launch-packet.js --markdown");
  console.log("```");
  console.log();
  console.log("## Target Choice");
  console.log();
  console.log("| Priority | Target | Use when | Surface ref |");
  console.log("|---:|---|---|---|");
  console.log(`| 1 | Show HN | Broad technical launch after live attribution and LLM discovery pass | \`${showHn.id}\` |`);
  console.log(`| 2 | Reddit LocalLLaMA | You want technical critique of local memory/scoring from local-LLM users | \`${localLlama.id}\` |`);
  console.log(`| 3 | X launch thread | The owner account has relevant AI/coding-agent audience | \`${xThread.id}\` |`);
  console.log(`| 4 | Reddit ClaudeAI | Relevant existing Claude thread or explicit owner-approved standalone post | \`${claudeAi.id}\` |`);
  console.log(`| 5 | Reddit ChatGPTCoding | Relevant existing Codex/ChatGPT coding thread or explicit owner-approved standalone post | \`${chatGptCoding.id}\` |`);
  console.log();
  console.log("## Copy Blocks");
  console.log();
  console.log("Show HN title:");
  console.log();
  console.log("```text");
  console.log(showHn.title);
  console.log("```");
  console.log();
  console.log("Show HN body:");
  console.log();
  console.log("```text");
  console.log(showHn.body);
  console.log("```");
  console.log();
  console.log("Optional attributed install reply if requested:");
  console.log();
  console.log("```bash");
  console.log(showHn.install_reply);
  console.log("```");
  console.log();
  console.log("## After Posting");
  console.log();
  console.log("Record the published URL and surface ref in `docs/ops/growth-report.md`, then monitor without bumping:");
  console.log();
  console.log("```bash");
  console.log("node scripts/prepare-social-launch-packet.js --receipt-packet hn-show <published-url>");
  console.log("node scripts/prepare-social-launch-packet.js --reply-packet hn-show");
  console.log("scripts/check-growth-live-state.sh v<tag>");
  console.log("scripts/run-approved-posthog-funnel-check.sh");
  console.log("```");
  console.log();
  console.log("Reply only to concrete questions, corrections, or useful technical discussion.");
}

function replyDrafts(row) {
  return [
    {
      label: "Short positioning",
      use_when: "Someone asks what AccInt is in one sentence.",
      text: [
        "AccInt is a local Work Model under coding agents: it records commitments, actions, approvals, outcomes, failures, and reusable paths, then retrieves the parts that actually earned trust after reality answered.",
        "",
        `Launch link for this thread: ${row.landing_url}`,
      ].join("\n"),
    },
    {
      label: "Difference from memory/RAG",
      use_when: "Someone asks how this differs from agent memory, RAG, or saved context.",
      text: [
        "The difference I care about is outcome credit. Plain memory recalls context. AccInt keeps a scored work state: what was promised, what ran, what needed approval, what passed, what failed, and which retrieved tokens or reusable paths were actually involved.",
        "",
        "Self-graded success stays weak. Tests, owner approval, and real replies are stronger evidence. The next run uses that scored history to predict a better path instead of just remembering more text.",
      ].join("\n"),
    },
    {
      label: "Privacy and locality",
      use_when: "Someone asks what leaves the machine.",
      text: [
        "The Work Model and memory stay local. There is no cloud memory account. The public telemetry contract is narrow: anonymous event names and coarse install/source refs for growth measurement, opt-out, with no prompts, files, memory contents, or Work Model data.",
        "",
        "Anything that would post, comment, pay, delete, submit, or use account identity is supposed to stop at an owner approval gate.",
      ].join("\n"),
    },
    {
      label: "Source boundary",
      use_when: "Someone asks whether it is open source.",
      text: [
        "The public repo is Apache-2.0 installer/docs/plugins/registry glue so the host integration can be audited. The local engine is shipped as a proprietary binary under the EULA, and the engine source is private.",
        "",
        "I am trying to be explicit about that boundary instead of implying the whole engine is open source.",
      ].join("\n"),
    },
    {
      label: "How to try it",
      use_when: "Someone asks for the install command or wants to reproduce the launch path.",
      text: [
        "The quickest path is the attributed launch link, then the one-line installer:",
        "",
        row.landing_url,
        "",
        row.posix,
        "",
        "The installer probes the machine and reports which embedder tier it can run instead of assuming a GPU or cloud model.",
      ].join("\n"),
    },
    {
      label: "What is proven",
      use_when: "Someone asks whether this is production mature.",
      text: [
        "It is young. What is real today: local MCP integration, host wiring for Claude Code/Codex/OpenCode/Cursor, a commitment/action/outcome ledger, MaxSim retrieval over scored memory, approval gates for external actions, and local checks around the public installer/distribution path.",
        "",
        "What I am still trying to prove publicly is adoption, retention, and whether the scored Work Model measurably makes repeated work faster and better outside my own usage.",
      ].join("\n"),
    },
  ];
}

function validateReplyDrafts(row) {
  const drafts = replyDrafts(row);
  if (drafts.length < 6) {
    die(`${row.id}: expected at least 6 reply drafts`);
  }
  const joined = drafts.map((draft) => draft.text).join("\n").toLowerCase();
  for (const phrase of FORBIDDEN_CLAIMS) {
    if (joined.includes(phrase)) {
      die(`${row.id}: reply draft contains forbidden overclaim: ${phrase}`);
    }
  }
  if (!joined.includes("no cloud memory account")) {
    die(`${row.id}: reply packet must state no cloud memory account`);
  }
  if (!joined.includes("proprietary binary") || !joined.includes("engine source is private")) {
    die(`${row.id}: reply packet must state source boundary`);
  }
  if (!joined.includes("no prompts, files, memory contents, or work model data")) {
    die(`${row.id}: reply packet must state telemetry exclusion boundary`);
  }
  if (!drafts.some((draft) => draft.text.includes(row.landing_url))) {
    die(`${row.id}: reply packet missing attributed landing URL`);
  }
  if (!drafts.some((draft) => draft.text.includes(row.posix))) {
    die(`${row.id}: reply packet missing attributed install snippet`);
  }
  for (const draft of drafts) {
    if (/https?:\/\/news\.ycombinator\.com\/submit/i.test(draft.text) || /https?:\/\/x\.com\/compose/i.test(draft.text)) {
      die(`${row.id}: reply draft must not include submit/compose URLs`);
    }
    if (draft.text.length > 1200) {
      die(`${row.id}: reply draft ${draft.label} is too long (${draft.text.length} chars)`);
    }
  }
}

function printReplyPacket(rows, surfaceId) {
  const id = surfaceId || "hn-show";
  const row = rows.find((item) => item.id === id);
  if (!row) {
    die(`unknown social launch surface ${id}`);
  }

  console.log("# Social Launch Reply Packet");
  console.log();
  console.log("READ ONLY: owner-review material only. Do not post, submit, comment, DM, pay, open compose forms, or use account identity without explicit owner approval for the exact reply.");
  console.log();
  console.log(`- Surface ref: \`${row.id}\``);
  console.log(`- Surface label: ${row.label}`);
  console.log(`- Attributed landing URL: ${row.landing_url}`);
  console.log(`- Source envelope: \`${row.source}\``);
  console.log();
  console.log("Use these only after an owner-approved post exists and a real comment asks for the point covered. Do not reply just to bump visibility.");
  console.log();
  console.log("Monitoring commands:");
  console.log();
  console.log("```bash");
  console.log(`node scripts/prepare-social-launch-packet.js --receipt-packet ${row.id} <published-url>`);
  console.log(`node scripts/prepare-social-launch-packet.js --reply-packet ${row.id}`);
  console.log("scripts/check-growth-live-state.sh v<tag>");
  console.log("scripts/run-approved-posthog-funnel-check.sh");
  console.log("```");
  console.log();

  for (const draft of replyDrafts(row)) {
    console.log(`## ${draft.label}`);
    console.log();
    console.log(`Use when: ${draft.use_when}`);
    console.log();
    console.log("```text");
    console.log(draft.text);
    console.log("```");
    console.log();
  }
}

function printReceiptPacket(rows, surfaceId, publishedUrl) {
  const id = surfaceId || "hn-show";
  const row = rows.find((item) => item.id === id);
  if (!row) {
    die(`unknown social launch surface ${id}`);
  }
  const url = publishedUrl || "<published-url>";
  if (publishedUrl && !/^https?:\/\/\S+$/i.test(publishedUrl)) {
    die(`published URL must be http(s) and contain no whitespace: ${publishedUrl}`);
  }
  const date = new Date().toISOString().slice(0, 10);

  console.log("# Social Launch Receipt Packet");
  console.log();
  console.log("READ ONLY: this packet records an owner-approved public post after it exists. It does not open the URL, post, comment, submit, DM, pay, or use account identity.");
  console.log();
  console.log("## Receipt");
  console.log();
  console.log(`- Surface ref: \`${row.id}\``);
  console.log(`- Surface label: ${row.label}`);
  console.log(`- Published URL: ${url}`);
  console.log(`- Attributed landing URL: ${row.landing_url}`);
  console.log(`- Source envelope: \`${row.source}\``);
  console.log();
  console.log("Append this row to `docs/ops/growth-report.md` after the owner-approved post is live:");
  console.log();
  console.log("```markdown");
  console.log("| Date | Surface ref | Published URL | Attributed landing URL | Follow-up boundary |");
  console.log("|---|---|---|---|---|");
  console.log(`| ${date} | \`${row.id}\` | ${url} | ${row.landing_url} | Monitor replies and attribution; do not bump or cross-post without fresh owner approval. |`);
  console.log("```");
  console.log();
  console.log("Monitor without bumping:");
  console.log();
  console.log("```bash");
  console.log("scripts/check-growth-live-state.sh v<tag>");
  console.log("scripts/run-approved-posthog-funnel-check.sh");
  console.log(`node scripts/prepare-social-launch-packet.js --reply-packet ${row.id}`);
  console.log("```");
}

const args = process.argv.slice(2);
const mode = args[0] || "--check";
if (mode === "-h" || mode === "--help") {
  usage();
  process.exit(0);
}
if (!["--check", "--decision-packet", "--reply-packet", "--receipt-packet", "--markdown", "--json"].includes(mode)) {
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
} else if (mode === "--decision-packet") {
  printDecisionPacket(rows);
} else if (mode === "--reply-packet") {
  printReplyPacket(rows, args[1]);
} else if (mode === "--receipt-packet") {
  printReceiptPacket(rows, args[1], args[2]);
} else if (mode === "--markdown") {
  printMarkdown(rows);
} else {
  printCheck(rows);
}
