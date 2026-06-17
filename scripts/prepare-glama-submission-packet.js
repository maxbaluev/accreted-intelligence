#!/usr/bin/env node
// Prepare and verify the owner-reviewable Glama submission packet.
//
// This script is intentionally local/read-only. It validates the Docker/MCP
// metadata Glama needs for the AccInt listing and prints the exact owner-held
// submission fields, but it never opens a browser, submits a form, comments on
// GitHub, pushes, pays, or uses account identity.

const fs = require("fs");
const path = require("path");

const REPO = process.env.ACC_GROWTH_REPO || "maxbaluev/accreted-intelligence";
const GLAMA_PATH = process.env.GLAMA_ACCINT_PATH || REPO;
const SERVER_NAME = "io.github.maxbaluev/accint";
const SERVER_JSON = "server.json";
const MCPB_MANIFEST = path.join("mcpb", "manifest.json");
const EXPECTED_TARGETS = [
  "aarch64-apple-darwin",
  "aarch64-unknown-linux-musl",
  "x86_64-unknown-linux-musl",
  "x86_64-pc-windows-msvc",
];

function usage() {
  console.error(`usage: node scripts/prepare-glama-submission-packet.js [--check|--markdown|--json] [tag]

Examples:
  node scripts/prepare-glama-submission-packet.js --check v0.1.6
  node scripts/prepare-glama-submission-packet.js --markdown v0.1.6

Output is review material only. It does not submit to Glama, push, comment,
dispatch workflows, pay, bypass anti-bot controls, or use account identity.
`);
}

function die(message, code = 1) {
  console.error(`GLAMA SUBMISSION PACKET: ${message}`);
  process.exit(code);
}

function readFile(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (err) {
    return null;
  }
}

function readJson(file) {
  const text = readFile(file);
  if (text === null) {
    die(`${file}: missing`);
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
}

function normalizeTag(tag, serverVersion) {
  let result = tag || `v${serverVersion}`;
  if (!result.startsWith("v")) {
    result = `v${result}`;
  }
  return result;
}

function addCheck(checks, label, ok, detail = "") {
  checks.push({ label, ok: Boolean(ok), detail });
}

function textHas(text, pattern) {
  if (text === null) {
    return false;
  }
  if (pattern instanceof RegExp) {
    return pattern.test(text);
  }
  return text.includes(pattern);
}

function checkFile(checks, file) {
  addCheck(checks, `${file}: present`, fs.existsSync(file));
}

function checkIncludes(checks, file, text, pattern, label) {
  addCheck(checks, `${file}: ${label}`, textHas(text, pattern));
}

function listToolNames(manifest) {
  const tools = manifest.tools;
  if (!Array.isArray(tools)) {
    return [];
  }
  return tools.map((tool) => String(tool.name || "")).filter(Boolean);
}

function packageByIdentifier(server, tag) {
  const packages = Array.isArray(server.packages) ? server.packages : [];
  const expected = new Map(
    EXPECTED_TARGETS.map((target) => [
      target,
      `https://github.com/${REPO}/releases/download/${tag}/acc-mcp-${tag}-${target}.mcpb`,
    ]),
  );
  const found = new Map();
  for (const pkg of packages) {
    const identifier = String(pkg.identifier || "");
    for (const [target, expectedIdentifier] of expected.entries()) {
      if (identifier === expectedIdentifier) {
        found.set(target, pkg);
      }
    }
  }
  return { packages, expected, found };
}

function packageChecks(checks, server, tag) {
  const { packages, expected, found } = packageByIdentifier(server, tag);
  addCheck(checks, `${SERVER_JSON}: four MCPB packages`, packages.length === EXPECTED_TARGETS.length, `found ${packages.length}`);

  for (const target of EXPECTED_TARGETS) {
    const pkg = found.get(target);
    addCheck(checks, `${SERVER_JSON}: ${target} package`, Boolean(pkg));
    if (!pkg) {
      continue;
    }
    addCheck(checks, `${SERVER_JSON}: ${target} registryType=mcpb`, pkg.registryType === "mcpb");
    addCheck(checks, `${SERVER_JSON}: ${target} stdio transport`, (pkg.transport || {}).type === "stdio");
    addCheck(
      checks,
      `${SERVER_JSON}: ${target} sha256`,
      /^[0-9a-f]{64}$/i.test(String(pkg.fileSha256 || "")),
    );
    addCheck(
      checks,
      `${SERVER_JSON}: ${target} release URL`,
      String(pkg.identifier || "") === expected.get(target),
    );
  }

  const meta = ((server._meta || {})["io.modelcontextprotocol.registry/publisher-provided"] || {});
  addCheck(checks, `${SERVER_JSON}: packager metadata`, meta.packager === "scripts/package-mcpb.sh");
  addCheck(
    checks,
    `${SERVER_JSON}: release target metadata`,
    JSON.stringify(meta.releaseTargets || []) === JSON.stringify(EXPECTED_TARGETS),
  );
}

function buildPacket(tag) {
  const server = readJson(SERVER_JSON);
  const manifest = readJson(MCPB_MANIFEST);
  const dockerfile = readFile("Dockerfile");
  const entrypoint = readFile(path.join("scripts", "docker-entrypoint.sh"));
  const wrapper = readFile(path.join("scripts", "acc-docker.sh"));
  const containerDoc = readFile(path.join("docs", "install", "container.md"));
  const punkpeyeFollowup = readFile(path.join("scripts", "prepare-punkpeye-glama-followup.sh"));
  const version = tag.replace(/^v/, "");

  const checks = [];
  [
    "Dockerfile",
    path.join("scripts", "docker-entrypoint.sh"),
    path.join("scripts", "acc-docker.sh"),
    path.join("docs", "install", "container.md"),
    path.join("scripts", "prepare-punkpeye-glama-followup.sh"),
    SERVER_JSON,
    MCPB_MANIFEST,
  ].forEach((file) => checkFile(checks, file));

  addCheck(checks, `${SERVER_JSON}: server name`, server.name === SERVER_NAME, String(server.name || ""));
  addCheck(checks, `${SERVER_JSON}: version matches tag`, server.version === version, `${server.version || "<missing>"} vs ${version}`);
  addCheck(checks, `${SERVER_JSON}: repository URL`, (server.repository || {}).url === `https://github.com/${REPO}`);
  addCheck(checks, `${SERVER_JSON}: website URL`, server.websiteUrl === "https://accint.xyz");
  packageChecks(checks, server, tag);

  addCheck(checks, `${MCPB_MANIFEST}: bundle name`, manifest.name === "accint");
  addCheck(checks, `${MCPB_MANIFEST}: repository URL`, ((manifest.repository || {}).url || "").includes(REPO));
  addCheck(checks, `${MCPB_MANIFEST}: binary server`, (manifest.server || {}).type === "binary");
  addCheck(checks, `${MCPB_MANIFEST}: entry point`, (manifest.server || {}).entry_point === "server/acc");
  const args = (((manifest.server || {}).mcp_config || {}).args || []).map(String);
  addCheck(checks, `${MCPB_MANIFEST}: MCP args include --db`, args.includes("--db"));
  addCheck(checks, `${MCPB_MANIFEST}: MCP args start server`, args.includes("mcp"));
  const tools = listToolNames(manifest);
  addCheck(checks, `${MCPB_MANIFEST}: acc_retrieve tool`, tools.includes("acc_retrieve"));
  addCheck(checks, `${MCPB_MANIFEST}: acc_act tool`, tools.includes("acc_act"));
  addCheck(checks, `${MCPB_MANIFEST}: no bundled substrate`, textHas(JSON.stringify(manifest), "acc.db") && !textHas(JSON.stringify(manifest), "substrate/"));

  checkIncludes(checks, "Dockerfile", dockerfile, "ARG ACC_VERSION=latest", "release version build arg");
  checkIncludes(checks, "Dockerfile", dockerfile, `https://github.com/${REPO}/releases/download`, "downloads public release binary");
  checkIncludes(checks, "Dockerfile", dockerfile, "sha256sums.txt", "downloads release checksum file");
  checkIncludes(checks, "Dockerfile", dockerfile, "sha256sum -c", "verifies release artifact checksum");
  checkIncludes(checks, "Dockerfile", dockerfile, "COPY scripts/docker-entrypoint.sh", "uses entrypoint script");
  checkIncludes(checks, "Dockerfile", dockerfile, 'HEALTHCHECK', "has container healthcheck");
  checkIncludes(checks, "Dockerfile", dockerfile, 'CMD ["mcp"]', "default command is MCP");
  checkIncludes(checks, "Dockerfile", dockerfile, 'ENTRYPOINT ["acc-entrypoint"]', "entrypoint is configured");
  checkIncludes(checks, "Dockerfile", dockerfile, 'VOLUME ["/data", "/models"]', "persists substrate and model caches");

  checkIncludes(checks, "scripts/docker-entrypoint.sh", entrypoint, 'cmd="${1:-mcp}"', "defaults to MCP mode");
  checkIncludes(checks, "scripts/docker-entrypoint.sh", entrypoint, 'exec acc --db "$ACC_DB" mcp', "execs stdio MCP server");
  checkIncludes(checks, "scripts/docker-entrypoint.sh", entrypoint, "ACC_NO_EMBEDDER", "supports no-model smoke/introspection");
  checkIncludes(checks, "scripts/docker-entrypoint.sh", entrypoint, "lightonai/LateOn", "pins CPU-compatible default model");

  checkIncludes(checks, "scripts/acc-docker.sh", wrapper, 'docker build --build-arg "ACC_VERSION=$VERSION"', "builds with release tag");
  checkIncludes(checks, "scripts/acc-docker.sh", wrapper, 'docker run --rm -i', "supports stdio MCP run");
  checkIncludes(checks, "scripts/acc-docker.sh", wrapper, 'ACC_NO_EMBEDDER', "passes no-model smoke env");
  checkIncludes(checks, "scripts/acc-docker.sh", wrapper, '/data/acc.db', "mounts substrate path");

  checkIncludes(checks, "docs/install/container.md", containerDoc, "Required smoke before registry submission", "documents required Docker smoke");
  checkIncludes(checks, "docs/install/container.md", containerDoc, `ACC_VERSION=${tag}`, "documents target release smoke");
  checkIncludes(checks, "docs/install/container.md", containerDoc, "Docker container smoke", "documents hosted Docker smoke workflow");
  checkIncludes(checks, "docs/install/container.md", containerDoc, "Docker-host verification is still required", "keeps Docker verification hold honest");

  checkIncludes(checks, "scripts/prepare-punkpeye-glama-followup.sh", punkpeyeFollowup, "never submits to Glama", "keeps Glama submission owner-held");
  checkIncludes(checks, "scripts/prepare-punkpeye-glama-followup.sh", punkpeyeFollowup, "badges/score.svg", "knows expected score badge URL");
  checkIncludes(checks, "scripts/prepare-punkpeye-glama-followup.sh", punkpeyeFollowup, "ACC_APPROVE_PUNKPEYE_GLAMA=1", "approval-gates PR badge update");

  const failures = checks.filter((check) => !check.ok);
  return {
    schema_version: 1,
    repo: REPO,
    tag,
    server_name: SERVER_NAME,
    server_version: server.version || "",
    glama: {
      submit_url: "https://glama.ai/mcp/servers",
      listing_url: `https://glama.ai/mcp/servers/${GLAMA_PATH}`,
      search_url: "https://glama.ai/mcp/servers?q=accint",
      score_badge_url: `https://glama.ai/mcp/servers/${GLAMA_PATH}/badges/score.svg`,
      expected_badge_markdown: `[![${GLAMA_PATH} MCP server](https://glama.ai/mcp/servers/${GLAMA_PATH}/badges/score.svg)](https://glama.ai/mcp/servers/${GLAMA_PATH})`,
    },
    docker: {
      dockerfile_path: "Dockerfile",
      build_command: `docker build --build-arg ACC_VERSION=${tag} -t accint-glama:${version} .`,
      smoke_commands: [
        `ACC_VERSION=${tag} scripts/acc-docker.sh status`,
        `ACC_VERSION=${tag} ACC_NO_EMBEDDER=1 scripts/acc-docker.sh doctor`,
        `ACC_VERSION=${tag} scripts/acc-docker.sh start`,
        "docker exec -i acc acc --db /data/acc.db status",
        "scripts/acc-docker.sh stop",
      ],
      mcp_command: "mcp",
      mounted_state: ["/data/acc.db", "/models"],
      no_model_smoke_env: "ACC_NO_EMBEDDER=1",
    },
    mcp: {
      tools: ["acc_retrieve", "acc_act"],
      transport: "stdio",
      default_db: "/data/acc.db",
      source_registry_name: SERVER_NAME,
    },
    owner_submission_fields: {
      repository_url: `https://github.com/${REPO}`,
      dockerfile_path: "Dockerfile",
      release_tag: tag,
      docker_build_arg: `ACC_VERSION=${tag}`,
      default_command: "mcp",
      expected_tools: "acc_retrieve, acc_act",
      notes: "The Dockerfile installs the verified public Linux release binary and defaults to stdio MCP mode. Docker-host smoke is still required before treating the listing as proven.",
    },
    checks,
    ready_for_owner_review: failures.length === 0,
    forbidden_without_approval: [
      "Glama form submission",
      "GitHub PR comment/edit/push",
      "workflow dispatch",
      "registry publish",
      "payment/CAPTCHA/private account action",
    ],
    known_holds: [
      "Actual Glama submission is owner-held and may require a logged-in browser.",
      "Docker-host smoke is required before relying on the container path as externally verified.",
      "Do not add the punkpeye Glama badge until the listing URL and score badge both return real AccInt content.",
    ],
  };
}

function printCheck(packet) {
  const failures = packet.checks.filter((check) => !check.ok);
  if (failures.length) {
    console.log("GLAMA SUBMISSION PACKET: FAIL");
    for (const failure of failures) {
      console.log(`  FAIL: ${failure.label}${failure.detail ? ` (${failure.detail})` : ""}`);
    }
    process.exit(1);
  }
  console.log("GLAMA SUBMISSION PACKET: PASS");
  console.log(`  repo: ${packet.repo}`);
  console.log(`  tag: ${packet.tag}`);
  console.log(`  server: ${packet.server_name} / ${packet.server_version}`);
  console.log(`  submit URL: ${packet.glama.submit_url}`);
  console.log(`  listing URL: ${packet.glama.listing_url}`);
  console.log(`  dockerfile: ${packet.docker.dockerfile_path}`);
  console.log(`  expected tools: ${packet.mcp.tools.join(", ")}`);
  console.log(`  checks: ${packet.checks.length}`);
  console.log(`  ready for owner review: ${packet.ready_for_owner_review ? "yes" : "not yet"}`);
}

function printMarkdown(packet) {
  console.log("# Glama Submission Packet");
  console.log();
  console.log("READ ONLY: this packet does not submit to Glama, push, comment, dispatch workflows, pay, bypass anti-bot controls, or use account identity.");
  console.log();
  console.log("## Current State");
  console.log();
  console.log(`- Repo: \`${packet.repo}\``);
  console.log(`- Release tag: \`${packet.tag}\``);
  console.log(`- MCP Registry name: \`${packet.server_name}\``);
  console.log(`- Server version: \`${packet.server_version}\``);
  console.log(`- Ready for owner review: ${packet.ready_for_owner_review ? "yes" : "not yet"}`);
  console.log();
  console.log("## Local Checks");
  console.log();
  for (const check of packet.checks) {
    console.log(`- ${check.ok ? "PASS" : "FAIL"}: \`${check.label}\`${check.detail ? ` - ${check.detail}` : ""}`);
  }
  console.log();
  console.log("## Manual Glama Submission Fields");
  console.log();
  console.log(`- Submit URL: ${packet.glama.submit_url}`);
  console.log(`- Repository URL: \`${packet.owner_submission_fields.repository_url}\``);
  console.log(`- Dockerfile path: \`${packet.owner_submission_fields.dockerfile_path}\``);
  console.log(`- Release tag: \`${packet.owner_submission_fields.release_tag}\``);
  console.log(`- Docker build arg: \`${packet.owner_submission_fields.docker_build_arg}\``);
  console.log(`- Default command: \`${packet.owner_submission_fields.default_command}\``);
  console.log(`- Expected MCP tools: \`${packet.owner_submission_fields.expected_tools}\``);
  console.log(`- Notes: ${packet.owner_submission_fields.notes}`);
  console.log();
  console.log("## Docker Smoke");
  console.log();
  console.log("Run on a Docker host before relying on the Glama listing as proven:");
  console.log();
  console.log("```bash");
  for (const command of packet.docker.smoke_commands) {
    console.log(command);
  }
  console.log("```");
  console.log();
  console.log("## After Glama Accepts");
  console.log();
  console.log(`- Listing URL: ${packet.glama.listing_url}`);
  console.log(`- Score badge URL: ${packet.glama.score_badge_url}`);
  console.log(`- Badge markdown: \`${packet.glama.expected_badge_markdown}\``);
  console.log("- Run `scripts/prepare-punkpeye-glama-followup.sh` first. Only run the approved mode if it reports `READY` and the owner approves that exact branch update.");
  console.log();
  console.log("## Known Holds");
  console.log();
  for (const hold of packet.known_holds) {
    console.log(`- ${hold}`);
  }
  console.log();
  console.log("## Forbidden Without Fresh Owner Approval");
  console.log();
  for (const item of packet.forbidden_without_approval) {
    console.log(`- ${item}`);
  }
}

const args = process.argv.slice(2);
let mode = "--check";
if (args[0] === "-h" || args[0] === "--help") {
  usage();
  process.exit(0);
}
if (["--check", "--markdown", "--json"].includes(args[0])) {
  mode = args.shift();
}
if (!["--check", "--markdown", "--json"].includes(mode)) {
  usage();
  process.exit(2);
}

const server = readJson(SERVER_JSON);
const tag = normalizeTag(args[0], server.version || "");
const packet = buildPacket(tag);

if (mode === "--json") {
  console.log(JSON.stringify(packet, null, 2));
} else if (mode === "--markdown") {
  printMarkdown(packet);
} else {
  printCheck(packet);
}
