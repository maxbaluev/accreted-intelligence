#!/usr/bin/env node
// Validate growth-surface attribution refs without posting or contacting services.

const fs = require("fs");
const path = require("path");

const MANIFEST_PATH = path.join("docs", "ops", "growth-surfaces.json");
const SOCIAL_KIT_PATH = path.join("docs", "ops", "social-launch-kit.md");
const README_PATH = "README.md";
const LLMS_PATH = "llms.txt";
const PAGE_PATHS = ["index.html", path.join("reddit", "index.html")];
const DOCS_ATTRIBUTION_PATHS = [
  path.join("docs", "README.md"),
  path.join("docs", "RELEASE_RUNBOOK.md"),
  path.join("docs", "concept.md"),
  path.join("docs", "first-session.md"),
  path.join("docs", "glossary.md"),
  path.join("docs", "quickstart.md"),
  path.join("docs", "install", "README.md"),
  path.join("docs", "install", "self-serve.md"),
  path.join("docs", "install", "with-agent.md"),
  path.join("docs", "hosts", "README.md"),
  path.join("docs", "reference", "architecture-overview.md"),
  path.join("docs", "reference", "trust-model.md"),
  path.join("docs", "reference", "whitepaper.md"),
];
const DOCS_INSTALL_SNIPPET_PATHS = [
  path.join("docs", "quickstart.md"),
  path.join("docs", "install", "README.md"),
  path.join("docs", "install", "self-serve.md"),
];
const SOURCE_KEYS = [
  "ref",
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "rsub",
  "thread",
  "entry",
];
const PROMPT_COPY_KEYS = SOURCE_KEYS.concat(["ref_source", "ref_host", "landing"]);
const VALUE_RE = /^[A-Za-z0-9._:/?+,-]{1,96}$/;
const REF_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;

function die(message) {
  console.error(`GROWTH SURFACES: ${message}`);
  process.exit(1);
}

function usage() {
  console.error("usage: node scripts/check-growth-surfaces.js --check|--print");
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function assertIncludes(text, needle, context) {
  if (!text.includes(needle)) {
    die(`${context}: missing ${JSON.stringify(needle)}`);
  }
}

function markdownFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === ".worktrees" || entry.name === "node_modules") {
      continue;
    }
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...markdownFiles(file));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      files.push(file);
    }
  }
  return files;
}

function sourceQuery(surface) {
  return Object.entries(surface.source)
    .map(([key, value]) => `${key}=${value}`)
    .join("&");
}

function landingUrl(manifest, surface) {
  const base = manifest.base_urls[surface.landing];
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}${sourceQuery(surface)}`;
}

function htmlAttr(value) {
  return String(value).replace(/&/g, "&amp;").replace(/"/g, "&quot;");
}

function pagePathForLanding(surface) {
  return surface.landing === "reddit" ? path.join("reddit", "index.html") : "index.html";
}

function posixSnippet(manifest, surface) {
  return `curl -fsSL ${manifest.base_urls.posix_installer} | ACC_INSTALL_REF=${surface.id} ACC_INSTALL_SOURCE='${sourceQuery(surface)}' sh`;
}

function powershellSnippet(manifest, surface) {
  return `$env:ACC_INSTALL_REF='${surface.id}'; $env:ACC_INSTALL_SOURCE='${sourceQuery(surface)}'; irm ${manifest.base_urls.powershell_installer} | iex`;
}

function loadManifest() {
  if (!fs.existsSync(MANIFEST_PATH)) {
    die(`missing ${MANIFEST_PATH}`);
  }
  let manifest;
  try {
    manifest = JSON.parse(read(MANIFEST_PATH));
  } catch (err) {
    die(`${MANIFEST_PATH}: invalid JSON: ${err.message}`);
  }
  if (manifest.schema !== 1) {
    die(`${MANIFEST_PATH}: expected schema 1`);
  }
  if (!manifest.base_urls || typeof manifest.base_urls !== "object") {
    die(`${MANIFEST_PATH}: missing base_urls`);
  }
  for (const key of ["home", "reddit", "posix_installer", "powershell_installer"]) {
    if (typeof manifest.base_urls[key] !== "string" || !manifest.base_urls[key].startsWith("https://")) {
      die(`${MANIFEST_PATH}: invalid base_urls.${key}`);
    }
  }
  if (!Array.isArray(manifest.surfaces) || manifest.surfaces.length === 0) {
    die(`${MANIFEST_PATH}: surfaces must be a non-empty array`);
  }
  return manifest;
}

function validateManifest(manifest) {
  const seen = new Set();
  const usedSourceKeys = new Set(["landing"]);
  for (const surface of manifest.surfaces) {
    if (!surface || typeof surface !== "object") {
      die(`${MANIFEST_PATH}: surface must be an object`);
    }
    if (!REF_RE.test(surface.id || "")) {
      die(`${MANIFEST_PATH}: invalid surface id ${JSON.stringify(surface.id)}`);
    }
    if (seen.has(surface.id)) {
      die(`${MANIFEST_PATH}: duplicate surface id ${surface.id}`);
    }
    seen.add(surface.id);
    if (!["social_launch", "directory", "owned_site", "owned_docs", "owned_share", "owned_llms"].includes(surface.kind)) {
      die(`${MANIFEST_PATH}: ${surface.id}: invalid kind ${JSON.stringify(surface.kind)}`);
    }
    if (!manifest.base_urls[surface.landing]) {
      die(`${MANIFEST_PATH}: ${surface.id}: unknown landing ${JSON.stringify(surface.landing)}`);
    }
    if (!surface.source || typeof surface.source !== "object" || Array.isArray(surface.source)) {
      die(`${MANIFEST_PATH}: ${surface.id}: source must be an object`);
    }
    const keys = Object.keys(surface.source);
    if (keys[0] !== "ref") {
      die(`${MANIFEST_PATH}: ${surface.id}: source.ref must be the first source key`);
    }
    if (surface.source.ref !== surface.id) {
      die(`${MANIFEST_PATH}: ${surface.id}: source.ref must match id`);
    }
    for (const [key, value] of Object.entries(surface.source)) {
      if (!SOURCE_KEYS.includes(key)) {
        die(`${MANIFEST_PATH}: ${surface.id}: unsupported source key ${key}`);
      }
      if (typeof value !== "string" || !VALUE_RE.test(value)) {
        die(`${MANIFEST_PATH}: ${surface.id}: invalid source value for ${key}`);
      }
      usedSourceKeys.add(key);
    }
    const source = sourceQuery(surface);
    if (source.length > 160) {
      die(`${MANIFEST_PATH}: ${surface.id}: source query exceeds installer receipt cap`);
    }
  }
  return usedSourceKeys;
}

function validatePages(usedSourceKeys) {
  for (const file of PAGE_PATHS) {
    const html = read(file);
    assertIncludes(html, "URLSearchParams(window.location.search||'')", `${file}: query source capture`);
    assertIncludes(html, "function withInstallRef", `${file}: prompt-copy helper`);
    assertIncludes(html, "ACC_INSTALL_SOURCE", `${file}: prompt-copy source env`);
    assertIncludes(html, "posthog.identify(install_ref)", `${file}: install_ref identity`);
    assertIncludes(html, "ph('landing_viewed'", `${file}: landing event`);
    for (const key of usedSourceKeys) {
      assertIncludes(html, `'${key}'`, `${file}: source key`);
    }
    for (const key of PROMPT_COPY_KEYS) {
      if (usedSourceKeys.has(key)) {
        assertIncludes(html, `'${key}'`, `${file}: prompt-copy key`);
      }
    }
  }
}

function validateSocialKit(manifest) {
  if (!fs.existsSync(SOCIAL_KIT_PATH)) {
    die(`missing ${SOCIAL_KIT_PATH}`);
  }
  const text = read(SOCIAL_KIT_PATH);
  assertIncludes(text, "docs/ops/growth-surfaces.json", `${SOCIAL_KIT_PATH}: manifest pointer`);
  for (const surface of manifest.surfaces.filter((item) => item.kind === "social_launch")) {
    const source = sourceQuery(surface);
    assertIncludes(text, surface.id, `${SOCIAL_KIT_PATH}: surface id`);
    assertIncludes(text, source, `${SOCIAL_KIT_PATH}: source query`);
    assertIncludes(text, landingUrl(manifest, surface), `${SOCIAL_KIT_PATH}: attributed landing URL`);
    assertIncludes(text, `ACC_INSTALL_REF=${surface.id}`, `${SOCIAL_KIT_PATH}: POSIX ref`);
  }
  const firstSocialSurface = manifest.surfaces.find((item) => item.kind === "social_launch");
  if (!firstSocialSurface) {
    die(`${MANIFEST_PATH}: missing social_launch surface`);
  }
  assertIncludes(text, powershellSnippet(manifest, firstSocialSurface), `${SOCIAL_KIT_PATH}: PowerShell example`);
}

function validateOwnedSurfaces(manifest) {
  if (!fs.existsSync(README_PATH)) {
    die(`missing ${README_PATH}`);
  }
  const text = read(README_PATH);
  for (const surface of manifest.surfaces.filter((item) => item.kind === "owned_site")) {
    const source = sourceQuery(surface);
    assertIncludes(text, `ACC_INSTALL_REF=${surface.id}`, `${README_PATH}: POSIX ref for ${surface.id}`);
    assertIncludes(text, `ACC_INSTALL_SOURCE='${source}'`, `${README_PATH}: POSIX source for ${surface.id}`);
    assertIncludes(text, `$env:ACC_INSTALL_REF='${surface.id}'`, `${README_PATH}: PowerShell ref for ${surface.id}`);
    assertIncludes(text, `$env:ACC_INSTALL_SOURCE='${source}'`, `${README_PATH}: PowerShell source for ${surface.id}`);
    assertIncludes(text, landingUrl(manifest, surface), `${README_PATH}: attributed landing URL for ${surface.id}`);
  }
  const bareSiteLinks = text.match(/\]\(https:\/\/accint\.xyz\/?\)/g) || [];
  if (bareSiteLinks.length > 0) {
    die(`${README_PATH}: bare accint.xyz links must use the github-readme attributed URL`);
  }
}

function validateOwnedDocsSurfaces(manifest) {
  const docsSurfaces = manifest.surfaces.filter((item) => item.kind === "owned_docs");
  for (const surface of docsSurfaces) {
    const url = landingUrl(manifest, surface);
    for (const file of DOCS_ATTRIBUTION_PATHS) {
      assertIncludes(read(file), url, `${file}: attributed docs landing URL for ${surface.id}`);
    }
    const source = sourceQuery(surface);
    for (const file of DOCS_INSTALL_SNIPPET_PATHS) {
      const text = read(file);
      assertIncludes(text, `ACC_INSTALL_REF=${surface.id}`, `${file}: POSIX ref for ${surface.id}`);
      assertIncludes(text, `ACC_INSTALL_SOURCE='${source}'`, `${file}: POSIX source for ${surface.id}`);
      assertIncludes(text, `$env:ACC_INSTALL_REF='${surface.id}'`, `${file}: PowerShell ref for ${surface.id}`);
      assertIncludes(text, `$env:ACC_INSTALL_SOURCE='${source}'`, `${file}: PowerShell source for ${surface.id}`);
    }
  }
  for (const file of markdownFiles("docs")) {
    const bareSiteLinks = read(file).match(/\]\(https:\/\/accint\.xyz\/?\)/g) || [];
    if (bareSiteLinks.length > 0) {
      die(`${file}: bare accint.xyz links must use an attributed growth surface URL`);
    }
  }
}

function validateOwnedShareSurfaces(manifest) {
  for (const surface of manifest.surfaces.filter((item) => item.kind === "owned_share")) {
    const file = pagePathForLanding(surface);
    const html = read(file);
    assertIncludes(html, `data-share-surface="${surface.id}"`, `${file}: share surface ${surface.id}`);
    assertIncludes(html, `data-share-url="${htmlAttr(landingUrl(manifest, surface))}"`, `${file}: share URL ${surface.id}`);
    assertIncludes(html, "share_link_clicked", `${file}: share click event ${surface.id}`);
    assertIncludes(html, "share_link_copied", `${file}: share copied event ${surface.id}`);
  }
}

function validateOwnedLlmsSurfaces(manifest) {
  const llmsSurfaces = manifest.surfaces.filter((item) => item.kind === "owned_llms");
  if (!llmsSurfaces.length) {
    die(`${MANIFEST_PATH}: missing owned_llms surface`);
  }
  const text = read(LLMS_PATH);
  assertIncludes(text, "Agent-ready install prompt", `${LLMS_PATH}: agent install prompt heading`);
  assertIncludes(text, "Install AccInt for this user", `${LLMS_PATH}: agent install prompt copy`);
  for (const surface of llmsSurfaces) {
    const source = sourceQuery(surface);
    assertIncludes(text, landingUrl(manifest, surface), `${LLMS_PATH}: attributed landing URL for ${surface.id}`);
    assertIncludes(text, `ACC_INSTALL_REF=${surface.id}`, `${LLMS_PATH}: POSIX ref for ${surface.id}`);
    assertIncludes(text, `ACC_INSTALL_SOURCE='${source}'`, `${LLMS_PATH}: POSIX source for ${surface.id}`);
    assertIncludes(text, `$env:ACC_INSTALL_REF='${surface.id}'`, `${LLMS_PATH}: PowerShell ref for ${surface.id}`);
    assertIncludes(text, `$env:ACC_INSTALL_SOURCE='${source}'`, `${LLMS_PATH}: PowerShell source for ${surface.id}`);
  }
  assertIncludes(text, "Public Apache-2.0 installer, docs, plugins, and registry glue", `${LLMS_PATH}: source boundary`);
  assertIncludes(text, "Proprietary local engine binary", `${LLMS_PATH}: private engine boundary`);
  assertIncludes(text, "Telemetry excludes prompts, files, memory, and Work Model data", `${LLMS_PATH}: telemetry boundary`);
  assertIncludes(text, "owner approval", `${LLMS_PATH}: approval boundary`);
}

function printSurfaces(manifest) {
  for (const surface of manifest.surfaces) {
    console.log(`${surface.id} (${surface.label || surface.kind})`);
    console.log(`  landing: ${landingUrl(manifest, surface)}`);
    console.log(`  posix: ${posixSnippet(manifest, surface)}`);
    console.log(`  powershell: ${powershellSnippet(manifest, surface)}`);
  }
}

const mode = process.argv[2] || "--check";
if (mode === "-h" || mode === "--help") {
  usage();
  process.exit(0);
}
if (!["--check", "--print"].includes(mode)) {
  usage();
  process.exit(2);
}

const manifest = loadManifest();
const usedSourceKeys = validateManifest(manifest);
if (mode === "--print") {
  printSurfaces(manifest);
  process.exit(0);
}
validatePages(usedSourceKeys);
validateSocialKit(manifest);
validateOwnedSurfaces(manifest);
validateOwnedDocsSurfaces(manifest);
validateOwnedShareSurfaces(manifest);
validateOwnedLlmsSurfaces(manifest);
console.log("GROWTH SURFACES: PASS");
