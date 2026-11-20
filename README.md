# Home Assistant Toolbox

A collection of Home Assistant automation blueprints, template sensors, and tools maintained by [@ccma14](https://github.com/ccma14).

---

## ♨️ Heat Pump Water Heater Manager

A complete package for 24-hour lifecycle management of Heat Pump Water Heaters (such as Rheem EcoNet). Overcomes thermal stratification by conditionally boosting early morning temperatures before showers, pre-heats with solar during the day, and resets in the evening.

### Components
1. **Automation Blueprint:** [`blueprints/automation/hpwh_daily_manager.yaml`](blueprints/automation/hpwh_daily_manager.yaml)
2. **True State of Charge (SoC) Template Sensor:** [`templates/water_heater_soc.yaml`](templates/water_heater_soc.yaml)

### Prerequisites & Integrations
- **Water Heater Integration:** Any heat pump water heater with climate and tank temperature entities (e.g., [esphome-econet](https://github.com/esphome-econet/esphome-econet) for Rheem/Ruud units).
- **Solar Production Forecast:** Any sensor providing today's estimated solar PV generation in kWh (common options include [Solcast](https://github.com/BJReplay/ha-solcast-solar), [Forecast.Solar](https://www.home-assistant.io/integrations/forecast_solar/), or custom templates).
- **Thermostatic Mixing Valve:** Installed at the tank hot water outlet to safely temper 140°F storage water down to fixture temperatures.
- **[Home Assistant Blueprints](https://www.home-assistant.io/docs/blueprint/):** Official documentation on importing and configuring automation blueprints.

---

## License

Copyright (c) 2026 Christian Czezatke.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License in the [LICENSE](LICENSE) file or at:

http://www.apache.org/licenses/LICENSE-2.0
