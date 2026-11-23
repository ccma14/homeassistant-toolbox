# Home Assistant Toolbox

A collection of Home Assistant automations, blueprints, template sensors, and dashboard cards maintained by [@ccma14](https://github.com/ccma14).

Each solution is packaged in its own directory with setup instructions, template sensors, blueprints, and custom cards.

---

## 📦 Available Solutions

| Solution | Status | Description | Link |
| :--- | :--- | :--- | :--- |
| **♨️ Heat Pump Water Heater Manager** | `Stable` | Automates daytime solar preheating, manages tank stratification, and provides a dashboard card with State of Charge (SoC) tracking. | [**Explore `hpwh/`**](hpwh/) |
| **❄️ ESPHome Mini-Split IR Thermostat** | `External Repo` | ESPHome package for Midea/Coolix-compatible mini-splits using external Home Assistant sensors and adaptive "Follow Me" temperature compensation. | [**ccma14/esphome-ir-thermostat ↗**](https://github.com/ccma14/esphome-ir-thermostat) |

---

## 🛠️ Repository Organization

Each directory in this repository represents a standalone project structured as follows:

```text
homeassistant-toolbox/
├── README.md               # Global catalog & project directory (this file)
└── <project_folder>/       # e.g., hpwh/
    ├── README.md           # Problem statement, theory, and setup instructions
    ├── blueprint.yaml      # Home Assistant automation blueprint
    ├── <project>.yaml      # Home Assistant sensor package
    └── <project>-card.js   # Lovelace dashboard card
```

---

## Getting Started

1. Pick the solution you want to install from the table above.
2. Open its directory (for example, [`hpwh/`](hpwh/)) and follow the instructions in its `README.md`.
3. Blueprints can be imported directly into Home Assistant using the raw GitHub URL of any `blueprint.yaml` file.

---

## License

Copyright (c) 2026 Christian Czezatke.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License in the [LICENSE](LICENSE) file or at:

http://www.apache.org/licenses/LICENSE-2.0
