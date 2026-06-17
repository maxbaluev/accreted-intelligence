#!/usr/bin/env node
// Validate and print the local PostHog dashboard spec without calling PostHog.
// This is an operator-prep step: it turns the runbook into stable artifacts and
// keeps dashboard creation approval-gated/manual.

const fs = require("fs");
const path = require("path");

const SPEC_PATH = path.join("docs", "ops", "posthog-dashboard.json");
const RUNBOOK_PATH = path.join("docs", "ops", "attribution-dashboard.md");

const REQUIRED_TILES = [
  "copy_to_first_run_funnel",
  "web_copy_source_leaderboard",
  "landing_to_copy_to_first_run_by_surface",
  "attributed_first_runs",
  "copy_to_attributed_first_run_by_surface",
  "visitor_share_loop",
  "activation_after_install",
];

function die(message) {
  throw new Error(message);
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function assert(condition, message) {
  if (!condition) {
    die(message);
  }
}

function includes(text, needle, context) {
  assert(text.includes(needle), `${context}: missing ${JSON.stringify(needle)}`);
}

function loadSpec() {
  const raw = read(SPEC_PATH);
  const spec = JSON.parse(raw);
  assert(spec.schema_version === 1, "schema_version must be 1");
  assert(spec.dashboard && spec.dashboard.name === "AccInt install attribution", "dashboard name mismatch");
  assert(Array.isArray(spec.dashboard.tiles), "dashboard.tiles must be an array");
  return spec;
}

function validateTileSet(spec, runbook) {
  const tiles = spec.dashboard.tiles;
  const bySlug = new Map(tiles.map((tile) => [tile.slug, tile]));
  REQUIRED_TILES.forEach((slug) => {
    assert(bySlug.has(slug), `missing required tile ${slug}`);
  });
  assert(tiles.length >= REQUIRED_TILES.length, "dashboard spec has fewer than required tiles");

  tiles.forEach((tile) => {
    assert(tile.slug && /^[a-z0-9_]+$/.test(tile.slug), `bad tile slug: ${tile.slug}`);
    assert(tile.title && typeof tile.title === "string", `${tile.slug}: missing title`);
    includes(runbook, tile.title, `${tile.slug}: runbook title`);
    assert(["funnel", "sql"].includes(tile.type), `${tile.slug}: unsupported type ${tile.type}`);
  });

  return bySlug;
}

function validateFunnel(tile, expectedEvents) {
  assert(Array.isArray(tile.steps), `${tile.slug}: steps must be an array`);
  assert(
    tile.steps.map((step) => step.event).join(",") === expectedEvents.join(","),
    `${tile.slug}: expected events ${expectedEvents.join(" -> ")}`
  );
  assert(tile.conversion_window_days === 7, `${tile.slug}: conversion window must be 7 days`);
  assert(Array.isArray(tile.breakdowns) && tile.breakdowns.length > 0, `${tile.slug}: missing breakdowns`);
}

function validateSql(tile, anchors) {
  assert(typeof tile.hogql === "string" && tile.hogql.trim(), `${tile.slug}: missing HogQL`);
  includes(tile.hogql, "FROM events", `${tile.slug}: HogQL`);
  includes(tile.hogql, "{filters}", `${tile.slug}: HogQL`);
  anchors.forEach((anchor) => includes(tile.hogql, anchor, `${tile.slug}: HogQL`));
}

function validatePrivacy(spec) {
  const raw = JSON.stringify(spec).toLowerCase();
  ["raw prompt text", "file contents", "memory contents", "work model data"].forEach((forbidden) => {
    includes(raw, forbidden, "privacy contract");
  });
  ["install_ref", "ref_source", "ref_host", "has_install_ref", "surface", "mode"].forEach((prop) => {
    includes(raw, prop, "allowed attribution properties");
  });
}

function validate() {
  const spec = loadSpec();
  const runbook = read(RUNBOOK_PATH);
  const bySlug = validateTileSet(spec, runbook);

  validateFunnel(bySlug.get("copy_to_first_run_funnel"), ["install_command_copied", "first_run"]);
  validateFunnel(bySlug.get("activation_after_install"), ["first_run", "first_retrieve", "daily_rollup"]);
  validateSql(bySlug.get("web_copy_source_leaderboard"), [
    "event = 'install_command_copied'",
    "uniqExact(distinct_id) AS copied_people",
    "properties.ref_source",
  ]);
  validateSql(bySlug.get("landing_to_copy_to_first_run_by_surface"), [
    "landings AS",
    "event = 'landing_viewed'",
    "install_command_copied",
    "first_run",
    "copy_rate_pct",
    "visit_to_run_pct",
  ]);
  validateSql(bySlug.get("attributed_first_runs"), [
    "event = 'first_run'",
    "properties.has_install_ref = 'true'",
    "attributed_first_runs",
  ]);
  validateSql(bySlug.get("copy_to_attributed_first_run_by_surface"), [
    "copies AS",
    "first_runs AS",
    "install_command_copied",
    "first_run",
    "conversion_pct",
    "interval 7 day",
  ]);
  validateSql(bySlug.get("visitor_share_loop"), [
    "event = 'share_link_copied'",
    "properties.surface = 'visitor-share'",
    "properties.ref = 'visitor-share'",
    "referred_visitors",
    "visitors_per_share",
    "referred_visit_to_run_pct",
  ]);
  validatePrivacy(spec);

  return spec;
}

function printSummary(spec) {
  console.log(`Dashboard: ${spec.dashboard.name}`);
  spec.dashboard.tiles.forEach((tile, index) => {
    console.log(`${index + 1}. ${tile.title} [${tile.type}]`);
    if (tile.type === "funnel") {
      console.log(`   steps: ${tile.steps.map((step) => step.event).join(" -> ")}`);
      console.log(`   breakdowns: ${tile.breakdowns.join(", ")}`);
    } else {
      console.log(`   display: ${tile.display}`);
      console.log("   hogql:");
      tile.hogql.split("\n").forEach((line) => console.log(`     ${line}`));
    }
  });
}

function renderFilter(filter) {
  const operator = filter.operator || "exact";
  return `${filter.property} ${operator} ${JSON.stringify(filter.value)}`;
}

function printUiPacket(spec) {
  console.log("# PostHog Insight Tile Packet");
  console.log();
  console.log("READ ONLY: this packet is generated from docs/ops/posthog-dashboard.json. It does not call PostHog or use credentials.");
  console.log();
  console.log(`Dashboard: ${spec.dashboard.name}`);
  console.log(`Description: ${spec.dashboard.description}`);
  console.log();
  console.log("Privacy contract:");
  console.log(`- Identity: ${spec.dashboard.privacy_contract.allowed_identity}`);
  console.log(`- Allowed source properties: ${spec.dashboard.privacy_contract.allowed_source_properties.join(", ")}`);
  console.log(`- Forbidden payloads: ${spec.dashboard.privacy_contract.forbidden_payloads.join(", ")}`);
  console.log();
  console.log(`Create these ${spec.dashboard.tiles.length} PostHog insights in order and add them to the dashboard.`);
  console.log();

  spec.dashboard.tiles.forEach((tile, index) => {
    console.log(`## ${index + 1}. ${tile.title}`);
    console.log();
    console.log(`Slug: \`${tile.slug}\``);
    console.log(`Insight type: \`${tile.type}\``);

    if (tile.type === "funnel") {
      console.log(`Conversion window: \`${tile.conversion_window_days} days\``);
      console.log(`Breakdowns: \`${tile.breakdowns.join("`, `")}\``);
      console.log();
      console.log("Steps:");
      tile.steps.forEach((step, stepIndex) => {
        console.log(`${stepIndex + 1}. Event: \`${step.event}\``);
        if (Array.isArray(step.filters) && step.filters.length) {
          console.log(`   Filters: ${step.filters.map(renderFilter).join("; ")}`);
        }
      });
    } else {
      console.log(`Display: \`${tile.display}\``);
      console.log();
      console.log("HogQL:");
      console.log();
      console.log("```sql");
      console.log(tile.hogql);
      console.log("```");
    }

    if (tile.expected_use) {
      console.log();
      console.log(`Expected use: ${tile.expected_use}`);
    }
    console.log();
  });
}

const mode = process.argv[2] || "--check";
try {
  const spec = validate();
  if (mode === "--json") {
    console.log(JSON.stringify(spec, null, 2));
  } else if (mode === "--print") {
    printSummary(spec);
  } else if (mode === "--ui-packet") {
    printUiPacket(spec);
  } else if (mode === "--check") {
    console.log("POSTHOG DASHBOARD SPEC: PASS");
  } else {
    console.error("usage: scripts/prepare-posthog-dashboard.js [--check|--print|--ui-packet|--json]");
    process.exit(2);
  }
} catch (err) {
  console.error(`POSTHOG DASHBOARD SPEC: FAIL: ${err.message}`);
  process.exit(1);
}
