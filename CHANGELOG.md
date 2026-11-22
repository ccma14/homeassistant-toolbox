# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-22

### Added
- **Card Theming:** Full support for Home Assistant light and dark themes using standard CSS variables (`--secondary-background-color`, `--divider-color`, semantic status colors).
- **Sections Dashboard Support:** Implemented `getGridOptions()` for optimal sizing in Home Assistant's default Sections layout.
- **Smart Stub Config:** `getStubConfig(hass)` automatically discovers live water heater climate and sensor entities on card load.
- **Visual Editor Polish:** Added `computeLabel` and `computeHelper` tooltips for `<ha-form>` in the visual card editor.
- **Accessibility:** Full keyboard navigation (`Enter` / `Space`), ARIA labels, `role="button"`, and `:focus-visible` outlines.
- **Drop-in Package (`hpwh.yaml`):** Self-contained Home Assistant package for `/config/packages/` or `/homeassistant/packages/`.
- **Testing Infrastructure:** Modular monorepo test runner (`scripts/test.sh`), component test suites in `hpwh/tests/`, and GitHub Actions CI.

### Changed
- **Centralized Calibration:** Centralized `inlet_cfg` and `tank_cfg` constants on the State of Charge sensor with downstream inheritance.
- **Blueprint Metadata:** Standardized on modern `triggers:` and `actions:` schema, added `source_url` for 1-click updates, and set `min_version: "2024.10.0"`.

### Fixed
- **Card Shower Toggle:** Resolved conflict between single-click (more-info dialog) and double-click (unit toggle).
- **Sensor Safeguards:** Added `has_value()` availability templates to prevent false 100% full readings when sensors drop offline.
- **Numeric Parsing:** Guarded NaN temperatures and missing SoC gauge displays in `hpwh-card.js`.
- **Logbook Queries:** Resolved repeated WebSocket query loop and stale event text in card status ticker.
- **Morning Recovery:** Improved timeout handling, added `wait_template`, and added recovery safety check across Home Assistant restarts.

## [1.0.0] - 2026-11-20

### Added
- Initial release of Solar & Stratification Heat Pump Water Heater Manager blueprint.
- State of charge, shower minutes, and shower gallons template sensors.
- Custom Lovelace card with thermal battery SVG dial and boost/reset controls.
