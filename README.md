# Home Assistant Toolbox

A collection of Home Assistant automation blueprints, template sensors, and dashboard widgets maintained by [@ccma14](https://github.com/ccma14).

---

## ♨️ Heat Pump Water Heater Manager

A complete package for 24-hour lifecycle management of Heat Pump Water Heaters (such as Rheem EcoNet). Overcomes thermal stratification by conditionally boosting early morning temperatures before showers, pre-heats with solar during the day, and resets in the evening.

### Components
1. **Automation Blueprint:** `blueprints/automation/hpwh_daily_manager.yaml`
2. **True State of Charge (SoC) Template Sensor:** `templates/water_heater_soc.yaml`

#### Requirements
- Heat pump water heater integration in Home Assistant (e.g., ESPHome EcoNet).
- Upper and lower tank temperature sensors.
- Solar PV forecast sensor (e.g., Solcast).
- Thermostatic mixing valve installed on tank outlet for safe 140°F storage.
