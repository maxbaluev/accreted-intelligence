#!/usr/bin/env node
// Static, zero-network verifier for the web -> installer -> app attribution stitch.
// It exercises the real withInstallRef() helper embedded in each page, so prompt-copy
// attribution cannot silently regress while the displayed install text stays unchanged.

const fs = require("fs");

const REF = "abc123def456";

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

function helperFrom(html) {
  const src = extractFunction(html, "withInstallRef");
  return new Function("install_ref", `return (${src});`)(REF);
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
  assertIncludes(html, "install_ref", `${file}: install_ref`);
}

function assertAgentPrompt(file, html, id) {
  const copied = helperFrom(html)(extractCode(html, id), "agent_prompt", "nix");
  assertIncludes(copied, `| ACC_INSTALL_REF=${REF} sh`, `${file}#${id}: POSIX prompt copy`);
  assertIncludes(copied, `$env:ACC_INSTALL_REF='${REF}'; irm`, `${file}#${id}: PowerShell prompt copy`);
}

function assertManualCommand(file, html, id, os) {
  const copied = helperFrom(html)(extractCode(html, id), "manual_command", os);
  if (os === "win") {
    assertIncludes(copied, `$env:ACC_INSTALL_REF='${REF}'; irm`, `${file}#${id}: manual Windows copy`);
  } else {
    assertIncludes(copied, `| ACC_INSTALL_REF=${REF} sh`, `${file}#${id}: manual POSIX copy`);
  }
}

function checkHome() {
  const file = "index.html";
  const html = read(file);
  assertInlineScriptsParse(file, html);
  assertPageIdentity(file, html);
  assertIncludes(html, "install_agent_prompt_copied", `${file}: prompt-copy event`);
  assertAgentPrompt(file, html, "agent-prompt");
  assertAgentPrompt(file, html, "agent-prompt2");
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
  assertIncludes(html, "reddit_agent_prompt_copied", `${file}: prompt-copy event`);
  assertAgentPrompt(file, html, "agent-prompt");
  assertManualCommand(file, html, "cmd-nix", "nix");
  assertManualCommand(file, html, "cmd-win", "win");
}

checkHome();
checkReddit();
console.log("attribution flow: ok");
