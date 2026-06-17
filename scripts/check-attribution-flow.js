#!/usr/bin/env node
// Static, zero-network verifier for the web -> installer -> app attribution stitch.
// It exercises the real withInstallRef() helper embedded in each page, so prompt-copy
// attribution cannot silently regress while the displayed install text stays unchanged.

const fs = require("fs");

const REF = "abc123def456";
const SOURCE_PROPS = {
  ref: "gh-awesome-list",
  utm_source: "github",
  utm_campaign: "launch",
  ref_source: "github",
  ref_host: "github.com",
  landing: "home",
};
const SOURCE_ENV =
  "ACC_INSTALL_SOURCE='ref=gh-awesome-list&utm_source=github&utm_campaign=launch&ref_source=github&ref_host=github.com&landing=home'";

function die(message) {
  throw new Error(message);
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function assertIncludes(text, needle, context) {
  if (!text.includes(needle)) {
    die(`${context}: missing ${JSON.stringify(needle)}`);
  }
}

function extractCode(html, id) {
  const re = new RegExp(`<code id="${id}">([\\s\\S]*?)<\\/code>`);
  const match = html.match(re);
  if (!match) {
    die(`missing code block #${id}`);
  }
  return match[1];
}

function extractFunction(html, name) {
  const start = html.indexOf(`function ${name}(`);
  if (start < 0) {
    die(`missing function ${name}`);
  }
  const bodyStart = html.indexOf("{", start);
  if (bodyStart < 0) {
    die(`malformed function ${name}`);
  }
  let depth = 0;
  for (let i = bodyStart; i < html.length; i += 1) {
    const ch = html[i];
    if (ch === "{") depth += 1;
    if (ch === "}") depth -= 1;
    if (depth === 0) {
      return html.slice(start, i + 1);
    }
  }
  die(`unterminated function ${name}`);
}

function helperFrom(html, sourceProps = SOURCE_PROPS, installRef = REF) {
  const src = extractFunction(html, "withInstallRef");
  return new Function("install_ref", "source_props", `return (${src});`)(installRef, sourceProps);
}

function referrerHelperFrom(html) {
  const src = extractFunction(html, "referrerSourceProps");
  return new Function(`return (${src});`)();
}

function assertEqual(actual, expected, context) {
  if (actual !== expected) {
    die(`${context}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertReferrerSource(file, html, referrer, expected) {
  const props = referrerHelperFrom(html)(referrer);
  Object.entries(expected).forEach(([key, value]) => {
    assertEqual(props[key], value, `${file}: ${referrer} ${key}`);
  });
}

function assertInlineScriptsParse(file, html) {
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
  scripts.forEach((script, i) => {
    try {
      new Function(script);
    } catch (err) {
      die(`${file}: inline script ${i + 1} parse failed: ${err.message}`);
    }
  });
}

function assertPageIdentity(file, html) {
  assertIncludes(html, "posthog.identify(install_ref)", `${file}: page identity`);
  assertIncludes(html, "register_for_session", `${file}: session properties`);
  assertIncludes(html, "ph('landing_viewed'", `${file}: landing event`);
  assertIncludes(html, "install_ref", `${file}: install_ref`);
  assertIncludes(html, "referrerSourceProps(document.referrer||'')", `${file}: referrer source`);
}

function assertAgentPrompt(file, html, id) {
  const copied = helperFrom(html)(extractCode(html, id), "agent_prompt", "nix");
  assertIncludes(copied, `| ACC_INSTALL_REF=${REF} ${SOURCE_ENV} sh`, `${file}#${id}: POSIX prompt copy`);
  assertIncludes(
    copied,
    `$env:ACC_INSTALL_REF='${REF}'; $env:ACC_INSTALL_SOURCE='ref=gh-awesome-list&utm_source=github&utm_campaign=launch&ref_source=github&ref_host=github.com&landing=home'; irm`,
    `${file}#${id}: PowerShell prompt copy`
  );
}

function assertPromptTrustBoundary(file, html, id) {
  const prompt = extractCode(html, id);
  assertIncludes(prompt, "public Apache-2.0 installer/docs/plugins/registry glue", `${file}#${id}: source boundary`);
  assertIncludes(prompt, "proprietary local engine binary", `${file}#${id}: binary boundary`);
  assertIncludes(prompt, "private engine source", `${file}#${id}: source-private boundary`);
  assertIncludes(prompt, "local Work Model data stays on my machine", `${file}#${id}: local data boundary`);
  assertIncludes(prompt, "no prompts, files, memory, or Work Model data", `${file}#${id}: telemetry boundary`);
  assertIncludes(prompt, "asks before anything leaves", `${file}#${id}: owner approval boundary`);
}

function assertSourceOnlyAgentPrompt(file, html, id) {
  const copied = helperFrom(html, { ref: "shared-prompt" }, "")(extractCode(html, id), "agent_prompt", "nix");
  assertIncludes(
    copied,
    `| ACC_INSTALL_REF='ref=shared-prompt' ACC_INSTALL_SOURCE='ref=shared-prompt' sh`,
    `${file}#${id}: source-only POSIX prompt copy`
  );
  assertIncludes(
    copied,
    `$env:ACC_INSTALL_REF='ref=shared-prompt'; $env:ACC_INSTALL_SOURCE='ref=shared-prompt'; irm`,
    `${file}#${id}: source-only PowerShell prompt copy`
  );
}

function assertManualCommand(file, html, id, os) {
  const copied = helperFrom(html)(extractCode(html, id), "manual_command", os);
  if (os === "win") {
    assertIncludes(
      copied,
      `$env:ACC_INSTALL_REF='${REF}'; $env:ACC_INSTALL_SOURCE='ref=gh-awesome-list&utm_source=github&utm_campaign=launch&ref_source=github&ref_host=github.com&landing=home'; irm`,
      `${file}#${id}: manual Windows copy`
    );
  } else {
    assertIncludes(copied, `| ACC_INSTALL_REF=${REF} ${SOURCE_ENV} sh`, `${file}#${id}: manual POSIX copy`);
  }
}

function checkHome() {
  const file = "index.html";
  const html = read(file);
  assertInlineScriptsParse(file, html);
  assertPageIdentity(file, html);
  assertReferrerSource(file, html, "https://github.com/maxbaluev/accreted-intelligence", {
    ref_host: "github.com",
    ref_source: "github",
  });
  assertReferrerSource(file, html, "https://www.reddit.com/r/ClaudeAI/comments/example", {
    ref_host: "reddit.com",
    ref_source: "reddit",
  });
  assertReferrerSource(file, html, "https://accint.xyz/docs/", {
    ref_host: undefined,
    ref_source: undefined,
  });
  assertIncludes(html, "install_agent_prompt_copied", `${file}: prompt-copy event`);
  assertIncludes(html, "share_link_copied", `${file}: visitor share event`);
  assertIncludes(html, "data-share-url=\"https://accint.xyz/?ref=visitor-share&amp;utm_source=share&amp;utm_campaign=organic\"", `${file}: visitor share URL`);
  assertAgentPrompt(file, html, "agent-prompt");
  assertPromptTrustBoundary(file, html, "agent-prompt");
  assertSourceOnlyAgentPrompt(file, html, "agent-prompt");
  assertAgentPrompt(file, html, "agent-prompt2");
  assertPromptTrustBoundary(file, html, "agent-prompt2");
  assertManualCommand(file, html, "cmd-nix", "nix");
  assertManualCommand(file, html, "cmd-nix2", "nix");
  assertManualCommand(file, html, "cmd-win", "win");
  assertManualCommand(file, html, "cmd-win2", "win");
}

function checkReddit() {
  const file = "reddit/index.html";
  const html = read(file);
  assertInlineScriptsParse(file, html);
  assertPageIdentity(file, html);
  assertReferrerSource(file, html, "https://github.com/maxbaluev/accreted-intelligence", {
    ref_host: "github.com",
    ref_source: "github",
  });
  assertReferrerSource(file, html, "https://news.ycombinator.com/item?id=1", {
    ref_host: "news.ycombinator.com",
    ref_source: "hacker_news",
  });
  assertIncludes(html, "reddit_landing_viewed", `${file}: reddit landing event`);
  assertIncludes(html, "reddit_community_clicked", `${file}: reddit community event`);
  assertIncludes(html, "reddit_post_template_clicked", `${file}: reddit template event`);
  assertIncludes(html, "reddit_agent_prompt_copied", `${file}: prompt-copy event`);
  assertIncludes(html, "share_link_clicked", `${file}: reddit share click event`);
  assertIncludes(html, "share_link_copied", `${file}: reddit share copied event`);
  assertIncludes(html, "data-share-url=\"https://accint.xyz/reddit/?ref=reddit-share&amp;utm_source=share&amp;utm_campaign=organic\"", `${file}: reddit share URL`);
  assertAgentPrompt(file, html, "agent-prompt");
  assertPromptTrustBoundary(file, html, "agent-prompt");
  assertSourceOnlyAgentPrompt(file, html, "agent-prompt");
  assertManualCommand(file, html, "cmd-nix", "nix");
  assertManualCommand(file, html, "cmd-win", "win");
}

checkHome();
checkReddit();
console.log("attribution flow: ok");
