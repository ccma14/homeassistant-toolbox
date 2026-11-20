# Home Assistant Blueprints

A repository of Home Assistant automation blueprints.

## Blueprints Included

### Solar & Stratification Heat Pump Water Heater Manager
- **File:** `blueprints/automation/hpwh_daily_manager.yaml`
- **Description:** 24-hour lifecycle management for heat pump water heaters (such as Rheem EcoNet). Overcomes thermal stratification by conditionally boosting early morning temperatures before showers, pre-heats with solar during the day, and resets in the evening.

#### Requirements
- Heat pump water heater integration in Home Assistant (e.g., ESPHome EcoNet).
- Upper and lower tank temperature sensors.
- Solar PV forecast sensor (e.g. Solcast).
- Thermostatic mixing valve installed on tank outlet for safe 140°F storage.
