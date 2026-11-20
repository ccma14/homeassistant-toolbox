# ♨️ Heat Pump Water Heater Manager

A complete, 24-hour lifecycle management system for Heat Pump Water Heaters (such as Rheem EcoNet, A.O. Smith, or custom ESPHome/Modbus setups) designed to overcome thermal stratification and maximize solar self-consumption.

---

## The Challenge

Heat pump water heaters suffer from severe **thermal stratification** after evening showers:
* Incoming cold water enters the bottom of the tank via the dip tube.
* Hot water rises and floats at the top.
* Because the upper tank temperature sensor remains near setpoint, the heat pump's internal thermostat never triggers overnight.
* On a subsequent low-solar or cloudy day without an early solar boost, morning showers can run lukewarm or cold.

![Tank Stratification](../images/tank_stratification.png)
*Figure 1: Widening gap between upper and lower tank temperatures following evening water draws.*

![Target Temperature Response](../images/target_temperature_response.png)
*Figure 2: Heat pump setpoint remains static while the lower tank drops into depleted temperatures.*

---

## The Solution

1. **Early Morning Assurance (06:30 AM):** Evaluates the lower tank temperature. If depleted (< 102°F), it calculates a dynamic overdrive setpoint (`upper + 4°F`, up to 140°F) to force the compressor on, runs until the lower tank reaches a safe reserve (112°F), and resets back to baseline.
2. **Daytime Solar Soak (10:00 AM):** Checks today's solar PV forecast. If high (> 25 kWh), boosts setpoint to 140°F to store free solar thermal energy. If low, maintains a reliable 125°F baseline.
3. **Evening Reset (16:00 PM):** Drops setpoint to 120°F to prevent compressor cycling on expensive evening/overnight grid power.
4. **True State of Charge (SoC):** A 40/60 volumetric weighted thermal storage sensor that tracks real usable energy and estimated shower gallons.
5. **Native Dashboard Card:** A complete, glanceable Lovelace card with SoC gauge, operating status, tank temperatures, and setpoint change logs.

---

## Files in this Package

| File | Description |
| :--- | :--- |
| [`blueprint.yaml`](blueprint.yaml) | Home Assistant automation blueprint for the 24-hr lifecycle manager. |
| [`templates.yaml`](templates.yaml) | Template sensor computing State of Charge (0–135%), thermal spread, and shower gallons. |
| [`dashboard.yaml`](dashboard.yaml) | Lovelace YAML card configuration using standard Home Assistant UI elements. |

---

## Step-by-Step Installation Guide

Follow these steps using the standard Home Assistant mechanisms:

### Step 1: Create the Status Logging Helper

The blueprint and dashboard card use an `input_text` helper to record setpoint changes with human-readable timestamps and temperatures.

#### Option A: Via Home Assistant UI (Recommended)
1. Go to **Settings > Devices & Services > Helpers**.
2. Click **+ Create Helper** (bottom right) and select **Text**.
3. Configure the helper:
   * **Name:** `Water Heater Last Action`
   * **Entity ID:** `input_text.water_heater_last_action`
   * **Maximum length:** `255`
4. Click **Create**.

#### Option B: Via `configuration.yaml`
Add the following to your `configuration.yaml`:
```yaml
input_text:
  water_heater_last_action:
    name: "Water Heater Last Action"
    max: 255
    icon: mdi:history
```
Then navigate to **Developer Tools > YAML** and click **Input Texts** to reload without restarting.

---

### Step 2: Install the State of Charge (SoC) Sensor

The SoC sensor computes true tank thermal reserves using a 40% upper / 60% lower volumetric weighting, accounting for cold water influx and the lower-wrap condenser coil.

#### If your `configuration.yaml` uses `template: !include templates.yaml`:
Open your `templates.yaml` and paste the contents of [`templates.yaml`](templates.yaml) (starting from the `- sensor:` line):
```yaml
- sensor:
    - name: "Water Heater State of Charge"
      unique_id: water_heater_state_of_charge
      unit_of_measurement: "%"
      state_class: measurement
      icon: mdi:battery-charging-high
      state: >-
        {% set cold_inlet = 65.0 %}
        {% set target_baseline = 120.0 %}
        {% set upper = states('sensor.water_heater_upper_tank_temperature') | float(target_baseline) %}
        {% set lower = states('sensor.water_heater_lower_tank_temperature') | float(target_baseline) %}
        {% set avg_temp = (upper * 0.4) + (lower * 0.6) %}
        {% set soc = ((avg_temp - cold_inlet) / (target_baseline - cold_inlet)) * 100 %}
        {{ [ [ soc | round(1), 0 ] | max, 135 ] | min }}
      attributes:
        upper_temperature: >-
          {{ states('sensor.water_heater_upper_tank_temperature') | float(0) }}
        lower_temperature: >-
          {{ states('sensor.water_heater_lower_tank_temperature') | float(0) }}
        average_temperature: >-
          {% set upper = states('sensor.water_heater_upper_tank_temperature') | float(120) %}
          {% set lower = states('sensor.water_heater_lower_tank_temperature') | float(120) %}
          {{ ((upper * 0.4) + (lower * 0.6)) | round(1) }}
        tank_spread: >-
          {% set upper = states('sensor.water_heater_upper_tank_temperature') | float(0) %}
          {% set lower = states('sensor.water_heater_lower_tank_temperature') | float(0) %}
          {{ (upper - lower) | round(1) }}
        usable_shower_gallons_est: >-
          {% set cold_inlet = 65.0 %}
          {% set shower_temp = 105.0 %}
          {% set upper = states('sensor.water_heater_upper_tank_temperature') | float(120) %}
          {% set lower = states('sensor.water_heater_lower_tank_temperature') | float(120) %}
          {% set avg_temp = (upper * 0.4) + (lower * 0.6) %}
          {% if avg_temp > cold_inlet %}
            {% set total_heat_btu = 65.0 * 8.33 * (avg_temp - cold_inlet) %}
            {% set gal_at_105 = total_heat_btu / (8.33 * (shower_temp - cold_inlet)) %}
            {{ [gal_at_105 | round(0), 0] | max }}
          {% else %}
            0
          {% endif %}
```

#### If adding directly to `configuration.yaml`:
Ensure the block is nested under `template:`, exactly as shown in [`templates.yaml`](templates.yaml).

#### Reloading:
Navigate to **Developer Tools > YAML** and click **Template Entities**. The sensor `sensor.water_heater_state_of_charge` will become active immediately without a restart.

---

### Step 3: Import and Configure the Blueprint

#### Option A: Direct Import via GitHub URL
1. Go to **Settings > Automations & Scenes > Blueprints**.
2. Click **Import Blueprint** (bottom right).
3. Paste the raw GitHub URL for [`blueprint.yaml`](https://raw.githubusercontent.com/ccma14/homeassistant-toolbox/main/hpwh/blueprint.yaml).
4. Click **Preview** and then **Import Blueprint**.

#### Option B: Manual File Placement
Copy [`blueprint.yaml`](blueprint.yaml) directly into your Home Assistant configuration directory at:
```text
/config/blueprints/automation/hpwh_daily_manager.yaml
```
Then reload blueprints under **Developer Tools > YAML > Automations**.

#### Creating the Automation:
1. In **Settings > Automations & Scenes > Blueprints**, find **Solar & Stratification Heat Pump Water Heater Manager** and click **Create Automation**.
2. Select your entities:
   * **Water Heater Climate Entity:** `climate.water_heater_econet_hpwh`
   * **Lower Tank Temperature Sensor:** `sensor.water_heater_lower_tank_temperature`
   * **Upper Tank Temperature Sensor:** `sensor.water_heater_upper_tank_temperature`
   * **Solar Forecast Sensor:** `sensor.solcast_pv_forecast_forecast_today`
   * **Status Logging Helper:** `input_text.water_heater_last_action`
3. Customize setpoints and schedule times as desired, then click **Save**.

---

### Step 4: Add the Dashboard Card

The dashboard card uses standard, native Home Assistant UI components (no HACS required):

1. Open your Home Assistant dashboard.
2. Click the **three dots** in the top-right corner and select **Edit Dashboard**.
3. Click **+ Add Card** at the bottom right.
4. Scroll to the bottom of the card list and select **Manual**.
5. Paste the complete YAML from [`dashboard.yaml`](dashboard.yaml).
6. Click **Save** and then **Done**.

---

## Safety & System Requirements
* **Thermostatic Mixing Valve:** A thermostatic tempering valve installed at the water heater outlet is **strongly recommended** when boosting storage to 140°F. This protects plumbing fixtures and prevents scald risk while giving you the full benefit of thermal energy storage.
* **Integrations Supported:** Any integration providing standard Home Assistant climate controls and temperature sensors (e.g. Rheem EcoNet via ESPHome, native cloud EcoNet, A.O. Smith, Stiebel Eltron, or Modbus).
