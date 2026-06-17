#!/usr/bin/env node
// Validate the maintainer social launch kit without posting or contacting services.

const fs = require("fs");
const path = require("path");

const KIT_PATH = path.join("docs", "ops", "social-launch-kit.md");

const REQUIRED_HEADINGS = [
  "# Social launch kit",
  "## Preflight",
  "## Attribution refs",
  "## Show HN",
  "## X / Twitter thread",
  "## Reddit",
  "## After posting",
];

const REQUIRED_REFS = [
  "hn-show",
  "x-launch-thread",
  "reddit-localllama",
  "reddit-claudeai",
  "reddit-chatgptcoding",
];

const REQUIRED_SNIPPETS = [
  "scripts/check-growth-readiness.sh",
  "scripts/check-growth-live-state.sh v<tag>",
  "scripts/check-live-attribution-flow.sh https://accint.xyz",
  "ACC_INSTALL_REF=hn-show",
  "ACC_INSTALL_SOURCE='ref=hn-show&utm_source=hacker_news&utm_campaign=launch'",
  "ACC_INSTALL_REF=x-launch-thread",
  "ACC_INSTALL_REF=reddit-localllama",
  "ACC_INSTALL_REF=reddit-claudeai",
  "ACC_INSTALL_REF=reddit-chatgptcoding",
  "public Apache-2.0 glue",
  "proprietary local engine binary",
  "private engine source",
  "does not authorize",
];

const FORBIDDEN = ["fully open source", "open-source engine", "public memory implementation"];

function die(message) {
  console.error(`SOCIAL LAUNCH KIT: ${message}`);
  process.exit(1);
}

function usage() {
  console.error("usage: node scripts/check-social-launch-kit.js --check");
}

const mode = process.argv[2] || "--check";
if (mode === "-h" || mode === "--help") {
  usage();
  process.exit(0);
}
if (mode !== "--check") {
  usage();
  process.exit(2);
}

if (!fs.existsSync(KIT_PATH)) {
  die(`missing ${KIT_PATH}`);
}

const text = fs.readFileSync(KIT_PATH, "utf8");

for (const heading of REQUIRED_HEADINGS) {
  if (!text.includes(heading)) {
    die(`missing heading ${JSON.stringify(heading)}`);
  }
}

for (const ref of REQUIRED_REFS) {
  const refCount = (text.match(new RegExp(ref.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) || []).length;
  if (refCount < 3) {
    die(`ref ${ref} appears only ${refCount} times`);
  }
  if (!text.includes(`ACC_INSTALL_REF=${ref}`) && !text.includes(`$env:ACC_INSTALL_REF='${ref}'`)) {
    die(`missing install snippet for ${ref}`);
  }
}

for (const snippet of REQUIRED_SNIPPETS) {
  if (!text.includes(snippet)) {
    die(`missing required snippet ${JSON.stringify(snippet)}`);
  }
}

const claimText = text
  .replace(/Do not claim:[\s\S]*?## Attribution refs/, "## Attribution refs")
  .toLowerCase();
for (const phrase of FORBIDDEN) {
  if (claimText.includes(phrase)) {
    die(`forbidden overclaim present: ${phrase}`);
  }
}
if (/(^|[^a-z])cloud memory account/.test(claimText) && !/(^|[^a-z])no cloud memory account/.test(claimText)) {
  die("forbidden overclaim present: cloud memory account");
}

if (/https?:\/\/news\.ycombinator\.com\/submit/i.test(text) || /https?:\/\/x\.com\/compose/i.test(text)) {
  die("launch kit must not include direct submit/compose URLs");
}

console.log("SOCIAL LAUNCH KIT: PASS");
