#!/usr/bin/env node
// Static verifier for the public MCP Registry discovery path.
//
// The official registry name and latest-version endpoint come from server.json.
// Keep the user-facing README/install docs aligned with that source of truth so
// people arriving from MCP directories can find the canonical MCPB metadata.

const fs = require("fs");

function die(message) {
  console.error(`REGISTRY DISCOVERY DOCS: ${message}`);
  process.exit(1);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
}

function read(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (err) {
    die(`${file}: ${err.message}`);
  }
}

function requireIncludes(file, text, needle) {
  if (!text.includes(needle)) {
    die(`${file}: missing ${JSON.stringify(needle)}`);
  }
}

const server = readJson("server.json");
const name = server.name;
const version = server.version;
if (!name || !version) {
  die("server.json must contain name and version");
}

const latestEndpoint = `https://registry.modelcontextprotocol.io/v0.1/servers/${encodeURIComponent(name)}/versions/latest`;
const packageTypes = new Set((server.packages || []).map((pkg) => pkg.registryType));
if (!packageTypes.has("mcpb")) {
  die("server.json must include MCPB packages");
}

const requirements = [
  {
    file: "README.md",
    needles: ["Official MCP Registry", name, latestEndpoint, "MCPB"],
  },
  {
    file: "docs/install/README.md",
    needles: ["Official MCP Registry", name, latestEndpoint, "MCPB"],
  },
  {
    file: "docs/quickstart.md",
    needles: ["Official MCP Registry", name],
  },
  {
    file: "docs/registry/mcp-registry.md",
    needles: [
      "Published user-facing state",
      name,
      latestEndpoint,
      `version: ${version}`,
      "registryType: mcpb",
    ],
  },
];

for (const { file, needles } of requirements) {
  const text = read(file);
  for (const needle of needles) {
    requireIncludes(file, text, needle);
  }
}

console.log("REGISTRY DISCOVERY DOCS: PASS");
