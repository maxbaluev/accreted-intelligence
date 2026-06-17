#!/usr/bin/env node
// Validate static site metadata that affects launch previews and search indexing.
//
// This is zero-network: it checks the checked-out HTML, robots.txt, sitemap.xml,
// and the local OG image file so social/SEO regressions are caught before push.

const fs = require("fs");
const path = require("path");

const SITE = "https://accint.xyz";
const OG_IMAGE = `${SITE}/og.png`;
const OG_IMAGE_PATH = "og.png";
const LLMS_URL = `${SITE}/llms.txt`;
const LLMS_PATH = "llms.txt";
const REQUIRED_PAGES = [
  {
    file: "index.html",
    canonical: `${SITE}/`,
    title: "Accreted Intelligence",
    descriptionNeedles: ["local Work Model", "Claude Code", "Codex"],
    ogTitleNeedle: "Accreted Intelligence",
    twitterDescriptionNeedle: "local Work Model",
  },
  {
    file: path.join("reddit", "index.html"),
    canonical: `${SITE}/reddit/`,
    title: "context window",
    descriptionNeedles: ["local Work Model", "Claude Code", "Codex"],
    ogTitleNeedle: "context window",
    twitterDescriptionNeedle: "accountable work state",
  },
];

function die(message) {
  console.error(`SITE METADATA: ${message}`);
  process.exit(1);
}

function read(file) {
  if (!fs.existsSync(file)) {
    die(`missing ${file}`);
  }
  return fs.readFileSync(file, "utf8");
}

function tagValue(html, attr, value, name = "content") {
  const re = new RegExp(`<meta\\s+[^>]*${attr}=["']${escapeRegExp(value)}["'][^>]*>`, "i");
  const match = html.match(re);
  if (!match) {
    return "";
  }
  const content = match[0].match(new RegExp(`${name}=["']([^"']+)["']`, "i"));
  return content ? content[1] : "";
}

function linkHref(html, rel) {
  const re = new RegExp(`<link\\s+[^>]*rel=["']${escapeRegExp(rel)}["'][^>]*>`, "i");
  const match = html.match(re);
  if (!match) {
    return "";
  }
  const href = match[0].match(/href=["']([^"']+)["']/i);
  return href ? href[1] : "";
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function assertIncludes(text, needle, context) {
  if (!text.includes(needle)) {
    die(`${context}: missing ${JSON.stringify(needle)}`);
  }
}

function assertEquals(actual, expected, context) {
  if (actual !== expected) {
    die(`${context}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function pngSize(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 24 || buf.toString("ascii", 1, 4) !== "PNG") {
    die(`${file}: not a PNG`);
  }
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  };
}

function checkPage(page) {
  const html = read(page.file);
  assertIncludes(html, "<title>", `${page.file}: title`);
  assertIncludes(html, page.title, `${page.file}: title copy`);

  const description = tagValue(html, "name", "description");
  for (const needle of page.descriptionNeedles) {
    assertIncludes(description, needle, `${page.file}: meta description`);
  }

  assertEquals(linkHref(html, "canonical"), page.canonical, `${page.file}: canonical`);
  assertIncludes(
    html,
    `<link rel="alternate" type="text/plain" href="${LLMS_URL}" title="llms.txt">`,
    `${page.file}: llms.txt alternate`
  );
  assertEquals(tagValue(html, "property", "og:url"), page.canonical, `${page.file}: og:url`);
  assertEquals(tagValue(html, "property", "og:type"), "website", `${page.file}: og:type`);
  assertEquals(tagValue(html, "property", "og:image"), OG_IMAGE, `${page.file}: og:image`);
  assertEquals(tagValue(html, "property", "og:image:width"), "1200", `${page.file}: og:image:width`);
  assertEquals(tagValue(html, "property", "og:image:height"), "630", `${page.file}: og:image:height`);
  assertEquals(tagValue(html, "property", "og:site_name"), "AccInt", `${page.file}: og:site_name`);
  assertIncludes(tagValue(html, "property", "og:title"), page.ogTitleNeedle, `${page.file}: og:title`);
  assertIncludes(tagValue(html, "property", "og:description"), "AccInt", `${page.file}: og:description`);
  assertIncludes(tagValue(html, "property", "og:image:alt"), "AccInt", `${page.file}: og:image:alt`);

  assertEquals(tagValue(html, "name", "twitter:card"), "summary_large_image", `${page.file}: twitter:card`);
  assertEquals(tagValue(html, "name", "twitter:image"), OG_IMAGE, `${page.file}: twitter:image`);
  assertIncludes(tagValue(html, "name", "twitter:title"), page.ogTitleNeedle, `${page.file}: twitter:title`);
  assertIncludes(
    tagValue(html, "name", "twitter:description"),
    page.twitterDescriptionNeedle,
    `${page.file}: twitter:description`
  );
}

function checkRobotsAndSitemap() {
  const robots = read("robots.txt");
  assertIncludes(robots, "User-agent: *", "robots.txt");
  assertIncludes(robots, "Allow: /", "robots.txt");
  assertIncludes(robots, `LLMs: ${LLMS_URL}`, "robots.txt");
  assertIncludes(robots, `${SITE}/sitemap.xml`, "robots.txt");

  const sitemap = read("sitemap.xml");
  assertIncludes(sitemap, '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">', "sitemap.xml");
  for (const page of REQUIRED_PAGES) {
    assertIncludes(sitemap, `<loc>${page.canonical}</loc>`, `sitemap.xml: ${page.canonical}`);
  }
  assertIncludes(sitemap, `<loc>${LLMS_URL}</loc>`, `sitemap.xml: ${LLMS_URL}`);
}

function checkLlmsTxt() {
  const text = read(LLMS_PATH);
  assertIncludes(text, "# AccInt", `${LLMS_PATH}: title`);
  assertIncludes(text, "local-first Work Model", `${LLMS_PATH}: positioning`);
  assertIncludes(text, "Claude Code, Codex, Cursor, and OpenCode", `${LLMS_PATH}: host fit`);
  assertIncludes(text, "ACC_INSTALL_REF=llms-txt", `${LLMS_PATH}: POSIX attribution`);
  assertIncludes(text, "$env:ACC_INSTALL_REF='llms-txt'", `${LLMS_PATH}: PowerShell attribution`);
  assertIncludes(text, "ref=llms-txt&utm_source=llm&utm_campaign=discovery", `${LLMS_PATH}: source attribution`);
  assertIncludes(text, "Public Apache-2.0 installer, docs, plugins, and registry glue", `${LLMS_PATH}: source boundary`);
  assertIncludes(text, "Proprietary local engine binary", `${LLMS_PATH}: private engine boundary`);
  assertIncludes(text, "Telemetry excludes prompts, files, memory, and Work Model data", `${LLMS_PATH}: telemetry boundary`);
  assertIncludes(text, "owner approval", `${LLMS_PATH}: authority boundary`);
}

for (const page of REQUIRED_PAGES) {
  checkPage(page);
}

const size = pngSize(OG_IMAGE_PATH);
assertEquals(size.width, 1200, `${OG_IMAGE_PATH}: width`);
assertEquals(size.height, 630, `${OG_IMAGE_PATH}: height`);
checkRobotsAndSitemap();
checkLlmsTxt();

console.log("SITE METADATA: PASS");
