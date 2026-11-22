# ♨️ Heat Pump Water Heater Manager

A Home Assistant automation blueprint and dashboard card for Heat Pump Water Heaters (such as Rheem EcoNet via ESPHome) to manage tank stratification and maximize daytime solar self-consumption.

---

## The Concept: The Water Heater as a Thermal Battery

A 65-gallon Heat Pump Water Heater is a zero-degradation thermal battery capable of storing **nearly 12 kWh of thermal energy**—rivaling the usable capacity of a residential home chemical battery.

Operating at an advertised Coefficient of Performance (COP) up to 4.0 (according to Rheem), banking that energy requires under 3.0 kWh of solar electricity, while a 140°F midday boost adds ~3.2 kWh of thermal storage. Boosting during peak solar hours and dropping the setpoint ahead of evening solar ramp-down allows the home to run through peak hours and overnight on stored heat—avoiding draining home battery reserves overnight while bypassing round-trip conversion losses.

---

## The Challenge: Stratification & The "False Full" Thermostat

Using the tank as a thermal battery works well, but evening water draws (such as showers, baths, or dishwashing) cause **thermal stratification**:
* Cold municipal water enters the bottom of the tank, displacing hot water in the lower ~60% of the volume.
* Hot water floats at the top, keeping the upper temperature sensor at or near the 120°F reduced setpoint.
* Because the upper sensor satisfies the thermostat, the heat pump does not turn on overnight.
* In the morning, only a thin layer of hot water remains. That hot layer is quickly exhausted during early showers, drawing cold water up from the bottom well before the daytime solar window begins.

![Tank Stratification](images/tank_stratification.png)
*Widening gap between upper and lower tank temperatures following evening water draws.*

---

## The Solution

1. **Early Morning Check (04:30 AM default):** Checks the lower tank temperature before morning showers. If depleted (< 102°F), it raises the setpoint slightly above the upper sensor (`upper + 4°F`, up to 140°F) to turn on the compressor, runs until the lower tank reaches a safe reserve (112°F), and resets back to baseline.
2. **Daytime Solar Boost (10:00 AM):** Checks today's solar PV forecast. If sunny (> 25 kWh forecast), boosts the setpoint to 140°F to store solar energy as hot water. If cloudy, maintains a 125°F baseline.
3. **Evening Reset (4:00 PM):** Drops the setpoint to 120°F ahead of sunset to prevent the compressor from running overnight on battery storage or grid power.
4. **Logbook Integration:** Automatically logs every setpoint change and trigger event to Home Assistant's native Logbook.
5. **(Optional) State of Charge (SoC):** Volumetric thermal storage tracking (0–100% nominal SoC + solar boost) and sensors for usable shower minutes and gallons.
6. **(Optional) Dashboard Card:** A Lovelace card with an SoC gauge, operating status, tank temperatures, and recent events.

---

## Files in this Package

| File | Type | Description |
| :--- | :--- | :--- |
| [`blueprint.yaml`](blueprint.yaml) | **Automation Blueprint** | Daily schedule and stratification manager. |
| [`hpwh.yaml`](hpwh.yaml) / [`templates.yaml`](templates.yaml) | *Sensors (Package or Templates)* | Template sensors for State of Charge (0–100% + solar boost), shower minutes, and gallons. |
| [`hpwh-card.js`](hpwh-card.js) | *Custom UI Card* | Lovelace card with battery gauge, metrics, and card editor. |

---

## Setup

### Step 1: Import and Configure the Blueprint

Import the blueprint using either method below:

#### Option A: 1-Click Import via My Home Assistant (Recommended)

[![Open your Home Assistant instance and show the blueprint import dialog with a specific blueprint pre-filled.](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fraw.githubusercontent.com%2Fccma14%2Fhomeassistant-toolbox%2Fmain%2Fhpwh%2Fblueprint.yaml)

*Or import manually via URL:*
1. In Home Assistant, go to **Settings > Automations & Scenes > Blueprints**.
2. Click **Import Blueprint** (bottom right).
3. Paste the raw GitHub URL:
   ```text
   https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/blueprint.yaml
   ```
4. Click **Preview** and then **Import Blueprint**.

#### Option B: Manual File Placement
Copy [`blueprint.yaml`](blueprint.yaml) directly into your Home Assistant configuration directory:
```text
/config/blueprints/automation/hpwh_daily_manager.yaml
```
Then reload blueprints under **Developer Tools > YAML > Automations**.

#### Creating the Automation:
1. In **Settings > Automations & Scenes > Blueprints**, find **Solar & Stratification Heat Pump Water Heater Manager** and click **Create Automation**.
2. Select your entities:
   * **Water Heater Climate Entity:** `climate.water_heater` (or your water heater entity)
   * **Lower Tank Temperature Sensor:** `sensor.water_heater_lower_tank_temperature`
   * **Upper Tank Temperature Sensor:** `sensor.water_heater_upper_tank_temperature`
   * **Solar Forecast Sensor:** `sensor.solar_forecast_today` (e.g. Solcast, Forecast.Solar)
3. Click **Save**. The automation will now manage morning recovery, solar boost, and evening reset. Every action is logged to your water heater's native Logbook.

---

## Optional: Visual Monitoring & Dashboard

If you'd like a visual dashboard with a thermal battery gauge, stratification spread, shower minutes, and gallon estimates:

### Step 2: Install the State of Charge (SoC) & Utility Sensors

The sensors compute true tank thermal reserves (0–100% nominal SoC + solar boost) and human-friendly shower minutes and gallons buffers using volumetric weighting.

#### Option A: Drop-in Home Assistant Package (Recommended)
Packages provide self-contained, drop-in YAML with zero indentation errors or manual editing of `configuration.yaml`.

1. Ensure packages are enabled in your `configuration.yaml` (add under `homeassistant:` if not already present):
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
2. Download [`hpwh.yaml`](hpwh.yaml) directly into your Home Assistant `/config/packages/` directory:
   ```bash
   wget -O /config/packages/hpwh.yaml https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/hpwh.yaml
   ```
   *(When updating in the future, re-running this command replaces the package cleanly with no manual editing).*
3. Reload template entities under **Developer Tools > YAML > Template Entities**.

#### Option B: Manual Include via `templates.yaml` / `configuration.yaml`
If your `configuration.yaml` uses `template: !include templates.yaml`, paste the contents of [`templates.yaml`](templates.yaml) starting from the `- sensor:` line.

#### Reloading:
Navigate to **Developer Tools > YAML** and click **Template Entities**. The sensors (`sensor.water_heater_state_of_charge`, `sensor.water_heater_shower_gallons`, `sensor.water_heater_shower_minutes`) will activate immediately without restarting Home Assistant.

---

### Step 3: Add the Dashboard Card

<p align="center">
  <img src="images/hpwh.png" width="400" alt="Heat Pump Water Heater Dashboard Card">
</p>

The card displays an SVG battery dial, shower metrics (minutes or gallons), tank temperatures, and manual boost/reset actions.

#### 1. Install the Card:
1. Download [`hpwh-card.js`](https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/hpwh-card.js) into your Home Assistant directory at `/config/www/hpwh-card.js`:
   ```bash
   wget -O /config/www/hpwh-card.js https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/hpwh-card.js
   ```
2. In Home Assistant, open the **Dashboard Resources** page:

   [![Open your Home Assistant instance and show your dashboard resources.](https://my.home-assistant.io/badges/lovelace_resources.svg)](https://my.home-assistant.io/redirect/lovelace_resources/)

   *(Or navigate to **Settings > Dashboards > 3 dots (top right) > Resources**, or open `/config/lovelace/resources` directly on your server. Note: Ensure **Advanced Mode** is toggled ON under your user profile for this menu to be visible).*
3. Click **+ Add Resource** (bottom right):
   * **URL:** `/local/hpwh-card.js?v=1.1.0`
   * **Resource type:** `JavaScript Module`
   *(Tip: When updating the card, increment the version query parameter, e.g. `?v=1.1.1`, to ensure browsers load the new file instead of using a cached copy).*
4. Refresh your browser window.

#### 2. Add to Dashboard:
1. Open your dashboard and click **Edit Dashboard** $\rightarrow$ **+ Add Card**.
2. Search for **Heat Pump Water Heater Card** (or select it from the card picker).
3. Select your entities in the card editor (**Water Heater**, **Power Sensor**, **SoC Sensor**, **Tank Temperatures**).
4. All metrics (SoC dial, Status, Target, and Temperatures) are **clickable** to view native Home Assistant history and graphs.

*(For users who manage dashboards in YAML mode, you can also add it directly with `type: custom:hpwh-card` and `entity: climate.water_heater`.)*

---

## Safety & System Requirements
* **Thermostatic Mixing Valve:** A thermostatic tempering valve installed at the water heater outlet is **strongly recommended** when boosting storage to 140°F. This protects plumbing fixtures and prevents scald risk while giving you the full benefit of thermal energy storage.
* **Dual Tank Temperature Sensors Required:** Stratification detection and morning assurance rely on having both upper and lower tank temperature measurements.
  * **Rheem EcoNet Water Heaters (Recommended):** The official Home Assistant cloud EcoNet integration only exposes a single aggregated temperature. To expose both built-in sensors, use the open-source [**`esphome-econet`**](https://github.com/esphome-econet/esphome-econet) project, which connects directly to the water heater's internal serial bus to provide 100% local control with discrete upper and lower temperature sensors (`sensor.water_heater_upper_tank_temperature` and `sensor.water_heater_lower_tank_temperature`).
  * **Other Equipment / External Probes:** You can experiment with external temperature sensors (e.g. 1-Wire DS18B20 probes placed under the upper and lower service panels), though surface readings will have more thermal lag than built-in sensors.
