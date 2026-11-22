/**
 * Test suite for hpwh-card.js
 * Validates version sync, HA visual editor schema, getGridOptions, and stub configuration.
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "../..");
const cardPath = path.resolve(repoRoot, "hpwh/hpwh-card.js");
const readmePath = path.resolve(repoRoot, "hpwh/README.md");

console.log("▶ Testing hpwh-card.js...");

// 1. Verify card file and README exist
assert(fs.existsSync(cardPath), "hpwh/hpwh-card.js must exist");
assert(fs.existsSync(readmePath), "hpwh/README.md must exist");

// 2. Mock browser environment to evaluate custom element class in Node
global.HTMLElement = class {};
global.customElements = {
  _registry: {},
  get: function(name) { return this._registry[name]; },
  define: function(name, cls) { this._registry[name] = cls; }
};
global.window = { customCards: [] };

// Suppress console.info version banner during tests
const origInfo = console.info;
console.info = () => {};
require(cardPath);
console.info = origInfo;

const HpwhCard = global.customElements.get("hpwh-card");
assert(HpwhCard, "hpwh-card custom element must be defined in customElements registry");

// 3. Verify Version Synchronization
const cardContent = fs.readFileSync(cardPath, "utf8");
const readmeContent = fs.readFileSync(readmePath, "utf8");

const versionMatch = cardContent.match(/const CARD_VERSION = ["']([^"']+)["']/);
assert(versionMatch, "CARD_VERSION constant must be defined in hpwh-card.js");
const cardVersion = versionMatch[1];

assert(
  readmeContent.includes(`hpwh-card.js?v=${cardVersion}`),
  `hpwh/README.md resource URL must include the current version (?v=${cardVersion})`
);
console.log(`  ✔ Version check passed (v${cardVersion} synchronized with README)`);

// 4. Verify getGridOptions for Sections Dashboard
assert(typeof HpwhCard.getGridOptions === "function", "HpwhCard must implement static getGridOptions()");
const gridOptions = HpwhCard.getGridOptions();
assert.strictEqual(gridOptions.columns, 12, "Grid options columns should default to 12");
assert.strictEqual(gridOptions.rows, 4, "Grid options rows should default to 4");
assert(gridOptions.min_columns <= 12, "min_columns must be <= 12");
assert(gridOptions.min_rows <= 4, "min_rows must be <= 4");
console.log("  ✔ getGridOptions() valid for Sections dashboard");

// 5. Verify getConfigForm, computeLabel, and computeHelper
assert(typeof HpwhCard.getConfigForm === "function", "HpwhCard must implement static getConfigForm()");
const configForm = HpwhCard.getConfigForm();
assert(Array.isArray(configForm.schema), "getConfigForm().schema must be an array");
assert(typeof configForm.computeLabel === "function", "getConfigForm() must provide computeLabel function");
assert(typeof configForm.computeHelper === "function", "getConfigForm() must provide computeHelper function");

const schemaNames = configForm.schema.map(field => field.name);
assert(schemaNames.includes("entity"), "Schema must include required 'entity' field");
assert(schemaNames.includes("boost_temperature"), "Schema must include 'boost_temperature' field");
assert(schemaNames.includes("reset_temperature"), "Schema must include 'reset_temperature' field");

for (const field of configForm.schema) {
  const label = configForm.computeLabel(field);
  assert(label && label !== field.name, `Field '${field.name}' must have a human-readable label in computeLabel`);
  // All fields should evaluate computeHelper without throwing
  const helper = configForm.computeHelper(field);
  assert(typeof helper === "string", `Helper for '${field.name}' must return a string`);
}
console.log(`  ✔ getConfigForm() valid (${schemaNames.length} fields with labels and helpers)`);

// 6. Verify getStubConfig
assert(typeof HpwhCard.getStubConfig === "function", "HpwhCard must implement static getStubConfig()");
const defaultStub = HpwhCard.getStubConfig();
assert(defaultStub.entity, "Default stub config must provide an entity");
assert.strictEqual(defaultStub.boost_temperature, 140, "Default boost temperature should be 140");
assert.strictEqual(defaultStub.reset_temperature, 120, "Default reset temperature should be 120");

// Test smart stub config with mock HA states
const mockHass = {
  states: {
    "climate.my_heatpump_water_heater": { state: "heat" },
    "sensor.my_heatpump_state_of_charge": { state: "85" },
    "sensor.my_heatpump_power": { state: "450" },
    "sensor.water_heater_upper_temp": { state: "135" },
    "sensor.water_heater_lower_temp": { state: "110" },
    "sensor.water_heater_shower_minutes": { state: "35" },
    "sensor.water_heater_shower_gallons": { state: "70" },
    "automation.my_hpwh_manager": { state: "on" }
  }
};
const smartStub = HpwhCard.getStubConfig(mockHass);
assert.strictEqual(smartStub.entity, "climate.my_heatpump_water_heater", "Smart stub should auto-detect climate entity");
assert.strictEqual(smartStub.soc_sensor, "sensor.my_heatpump_state_of_charge", "Smart stub should auto-detect SoC sensor");
assert.strictEqual(smartStub.power_sensor, "sensor.my_heatpump_power", "Smart stub should auto-detect power sensor");
assert.strictEqual(smartStub.upper_temp_sensor, "sensor.water_heater_upper_temp", "Smart stub should auto-detect upper temp");
assert.strictEqual(smartStub.lower_temp_sensor, "sensor.water_heater_lower_temp", "Smart stub should auto-detect lower temp");
assert.strictEqual(smartStub.automation_entity, "automation.my_hpwh_manager", "Smart stub should auto-detect automation");
console.log("  ✔ getStubConfig(hass) valid (fallback defaults & smart auto-discovery passed)");

// 7. Verify Custom Card Picker Registration
const registeredCard = global.window.customCards.find(c => c.type === "hpwh-card");
assert(registeredCard, "hpwh-card must be registered in window.customCards");
assert(registeredCard.name, "Registered card must have a name");
assert(registeredCard.description, "Registered card must have a description");
console.log("  ✔ customCards registration valid for Home Assistant card picker");

console.log("All hpwh-card tests passed successfully!\n");
