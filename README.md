# Home Assistant Toolbox

A collection of modular, production-ready Home Assistant automations, blueprints, template sensors, and dashboards maintained by [@ccma14](https://github.com/ccma14).

Each solution is packaged in its own self-contained directory with dedicated setup guides, template sensors, blueprints, and Lovelace cards.

---

## 📦 Available Solutions

| Solution | Status | Description | Link |
| :--- | :--- | :--- | :--- |
| **♨️ Heat Pump Water Heater Manager** | `Stable` | Overcomes tank thermal stratification, pre-heats with solar PV forecast, tracks true volumetric State of Charge (SoC), and provides glanceable dashboard controls. | [**Explore `hpwh/`**](hpwh/) |
| **❄️ ESPHome Mini-Split IR Thermostat** | `External Repo` | ESPHome package for Midea/Coolix-compatible mini-splits using external Home Assistant sensors and adaptive "Follow Me" temperature compensation. | [**ccma14/esphome-ir-thermostat ↗**](https://github.com/ccma14/esphome-ir-thermostat) |
| **⚡ Smart EV Solar Charging** | `Planned` | Dynamically throttles EV charging current based on real-time solar surplus and utility time-of-use (TOU) export rates. | Coming soon |

---

## 🛠️ Repository Organization

Each directory in this repository represents an end-to-end appliance or energy management package structured as follows:

```text
homeassistant-toolbox/
├── README.md               # Global catalog & project directory (this file)
└── <solution_folder>/      # e.g., hpwh/, ev_charger/
    ├── README.md           # In-depth problem statement, theory & step-by-step setup
    ├── blueprint.yaml      # Ready-to-import Home Assistant automation blueprint
    ├── templates.yaml      # Jinja template sensors and attributes
    └── <solution>-card.js  # Dedicated Lovelace dashboard card
```

---

## 🚀 Quick Start

1. Pick the solution you want to install from the table above.
2. Open its folder (for example, [`hpwh/`](hpwh/)) and follow the step-by-step installation instructions in its `README.md`.
3. Blueprints can be imported directly into Home Assistant using the raw GitHub URL of any `blueprint.yaml` file.

---

## License

Copyright (c) 2026 Christian Czezatke.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License in the [LICENSE](LICENSE) file or at:

http://www.apache.org/licenses/LICENSE-2.0
