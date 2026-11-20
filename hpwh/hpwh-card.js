/**
 * Heat Pump Water Heater Custom Lovelace Card
 * Repository: https://github.com/ccma14/homeassistant-toolbox
 * License: Apache 2.0
 */

class HpwhCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._initialized = false;
    this._elements = {};
  }

  setConfig(config) {
    if (!config.entity) {
      throw new Error("Please define a water heater climate entity.");
    }
    this._config = {
      title: "♨️ Heat Pump Water Heater",
      shower_display: "minutes",
      ...config
    };
    if (this._initialized) {
      this._updateContent();
    }
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._initialized) {
      this._initDOM();
      this._initialized = true;
    }
    this._updateContent();
  }

  static getConfigForm() {
    return {
      schema: [
        {
          name: "entity",
          required: true,
          selector: { entity: { domain: "climate" } }
        },
        {
          name: "power_sensor",
          selector: { entity: { domain: "sensor", device_class: "power" } }
        },
        {
          name: "soc_sensor",
          selector: { entity: { domain: "sensor" } }
        },
        {
          name: "upper_temp_sensor",
          selector: { entity: { domain: "sensor", device_class: "temperature" } }
        },
        {
          name: "lower_temp_sensor",
          selector: { entity: { domain: "sensor", device_class: "temperature" } }
        },
        {
          name: "automation_entity",
          selector: { entity: { domain: "automation" } }
        },
        {
          name: "shower_display",
          selector: {
            select: {
              options: [
                { value: "minutes", label: "Shower Minutes (e.g. 38 min)" },
                { value: "gallons", label: "Gallons (e.g. 77 gal)" }
              ]
            }
          }
        },
        {
          name: "title",
          selector: { text: {} }
        }
      ]
    };
  }

  static getStubConfig() {
    return {
      title: "♨️ Heat Pump Water Heater",
      shower_display: "minutes",
      entity: "climate.water_heater",
      power_sensor: "sensor.water_heater_power",
      soc_sensor: "sensor.water_heater_state_of_charge",
      upper_temp_sensor: "sensor.water_heater_upper_tank_temperature",
      lower_temp_sensor: "sensor.water_heater_lower_tank_temperature",
      automation_entity: "automation.solar_stratification_heat_pump_water_heater_manager"
    };
  }

  getCardSize() {
    return 6;
  }

  _callService(service, serviceData) {
    if (!this._hass) return;
    const [domain, action] = service.split(".");
    this._hass.callService(domain, action, serviceData);
  }

  _fireMoreInfo(entityId) {
    if (!entityId) return;
    const event = new CustomEvent("hass-more-info", {
      detail: { entityId },
      bubbles: true,
      composed: true
    });
    this.dispatchEvent(event);
  }

  _initDOM() {
    this.shadowRoot.innerHTML = `
      <style>
        ha-card {
          padding: 16px;
          background: var(--ha-card-background, var(--card-background-color, #1c1c1e));
          border-radius: var(--ha-card-border-radius, 12px);
          box-shadow: var(--ha-card-box-shadow, none);
          font-family: var(--paper-font-body1_-_font-family, system-ui, -apple-system, sans-serif);
          color: var(--primary-text-color, #ffffff);
          box-sizing: border-box;
          user-select: none;
          min-height: 290px;
        }
        .header {
          font-size: 1.15rem;
          font-weight: 600;
          margin-bottom: 14px;
          color: var(--primary-text-color, #ffffff);
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .top-row {
          display: grid;
          grid-template-columns: 1fr 1.3fr;
          gap: 12px;
          align-items: center;
          margin-bottom: 14px;
        }
        .soc-container {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          background: rgba(255, 255, 255, 0.04);
          border-radius: 10px;
          padding: 8px;
          cursor: pointer;
          transition: background 0.2s, transform 0.1s;
        }
        .soc-container:hover {
          background: rgba(255, 255, 255, 0.08);
        }
        .soc-container:active {
          transform: scale(0.98);
        }
        .soc-svg {
          width: 85px;
          height: 85px;
          transform: rotate(-90deg);
        }
        .soc-bg {
          fill: none;
          stroke: rgba(255, 255, 255, 0.1);
          stroke-width: 6;
        }
        .soc-meter {
          fill: none;
          stroke: #4caf50;
          stroke-width: 6;
          stroke-linecap: round;
          transition: stroke-dasharray 0.5s ease, stroke 0.3s;
        }
        .soc-label {
          position: absolute;
          font-size: 1.25rem;
          font-weight: 700;
          text-align: center;
        }
        .soc-sub {
          font-size: 0.72rem;
          opacity: 0.7;
          margin-top: 4px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .status-stack {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .pill {
          background: rgba(255, 255, 255, 0.04);
          border-radius: 10px;
          padding: 8px 12px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          cursor: pointer;
          transition: background 0.2s, transform 0.1s;
        }
        .pill:hover {
          background: rgba(255, 255, 255, 0.08);
        }
        .pill:active {
          transform: scale(0.98);
        }
        .pill-label {
          font-size: 0.8rem;
          opacity: 0.7;
        }
        .pill-value {
          font-size: 0.95rem;
          font-weight: 600;
          text-transform: capitalize;
          display: flex;
          align-items: center;
          gap: 4px;
        }
        .glance-row {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          background: rgba(255, 255, 255, 0.04);
          border-radius: 10px;
          padding: 8px 4px;
          text-align: center;
          margin-bottom: 12px;
        }
        .glance-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 2px;
          cursor: pointer;
          padding: 4px;
          border-radius: 8px;
          transition: background 0.2s, transform 0.1s;
        }
        .glance-item:hover {
          background: rgba(255, 255, 255, 0.08);
        }
        .glance-item:active {
          transform: scale(0.96);
        }
        .glance-item:not(:last-child) {
          border-right: 1px solid rgba(255, 255, 255, 0.08);
        }
        .glance-sub {
          font-size: 0.72rem;
          opacity: 0.7;
        }
        .glance-val {
          font-size: 1rem;
          font-weight: 600;
        }
        .auto-row {
          background: rgba(255, 255, 255, 0.03);
          border-radius: 8px;
          padding: 6px 10px;
          font-size: 0.78rem;
          color: var(--secondary-text-color, rgba(255, 255, 255, 0.65));
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 12px;
          cursor: pointer;
          transition: background 0.2s, color 0.2s;
        }
        .auto-row:hover {
          background: rgba(255, 255, 255, 0.08);
          color: var(--primary-text-color, #ffffff);
        }
        .actions-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
        }
        .btn {
          background: rgba(255, 255, 255, 0.06);
          border: 1px solid rgba(255, 255, 255, 0.1);
          border-radius: 8px;
          padding: 10px;
          font-size: 0.88rem;
          font-weight: 600;
          color: var(--primary-text-color, #ffffff);
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
          transition: background 0.2s, transform 0.1s;
        }
        .btn:hover {
          background: rgba(255, 255, 255, 0.12);
        }
        .btn:active {
          transform: scale(0.98);
        }
        .btn-boost {
          border-color: rgba(255, 152, 0, 0.3);
        }
      </style>

      <ha-card>
        <div class="header">
          <span id="card-title">♨️ Heat Pump Water Heater</span>
        </div>

        <div class="top-row">
          <div class="soc-container" id="click-soc" title="Click to view State of Charge history">
            <div style="position: relative; display: flex; align-items: center; justify-content: center;">
              <svg class="soc-svg" viewBox="0 0 70 70">
                <circle class="soc-bg" cx="35" cy="35" r="30"></circle>
                <circle class="soc-meter" id="soc-meter" cx="35" cy="35" r="30" stroke-dasharray="0 188.5"></circle>
              </svg>
              <div class="soc-label" id="soc-label">--%</div>
            </div>
            <div class="soc-sub">Thermal Storage</div>
          </div>

          <div class="status-stack">
            <div class="pill" id="click-status" title="Click to view power / status history">
              <span class="pill-label">HPWH Status</span>
              <span class="pill-value" id="status-val">Idle</span>
            </div>
            <div class="pill" id="click-target" title="Click to adjust water heater temperature">
              <span class="pill-label">Target Setpoint</span>
              <span class="pill-value" id="target-val">--</span>
            </div>
          </div>
        </div>

        <div class="glance-row">
          <div class="glance-item" id="click-upper" title="Click to view Upper Tank history">
            <span class="glance-sub">Upper Tank</span>
            <span class="glance-val" id="upper-val">--</span>
          </div>
          <div class="glance-item" id="click-lower" title="Click to view Lower Tank history">
            <span class="glance-sub">Lower Tank</span>
            <span class="glance-val" id="lower-val">--</span>
          </div>
          <div class="glance-item" id="click-shower" title="Click to view Shower Buffer details">
            <span class="glance-sub">Shower Buffer</span>
            <span class="glance-val" id="shower-val">--</span>
          </div>
        </div>

        <div class="auto-row" id="click-auto" title="Click to view automation history">
          <span id="auto-text">⚡ Automation: Active & monitoring</span>
        </div>

        <div class="actions-row">
          <button class="btn btn-boost" id="btn-boost">
            ☀️ Boost 140°F
          </button>
          <button class="btn" id="btn-reset">
            🔄 Reset 120°F
          </button>
        </div>
      </ha-card>
    `;

    // Cache elements for high-performance updates without DOM recreation
    this._elements = {
      title: this.shadowRoot.getElementById("card-title"),
      socMeter: this.shadowRoot.getElementById("soc-meter"),
      socLabel: this.shadowRoot.getElementById("soc-label"),
      statusVal: this.shadowRoot.getElementById("status-val"),
      targetVal: this.shadowRoot.getElementById("target-val"),
      upperVal: this.shadowRoot.getElementById("upper-val"),
      lowerVal: this.shadowRoot.getElementById("lower-val"),
      showerVal: this.shadowRoot.getElementById("shower-val"),
      showerItem: this.shadowRoot.getElementById("click-shower"),
      autoText: this.shadowRoot.getElementById("auto-text")
    };

    // Attach click events once
    this.shadowRoot.getElementById("click-soc")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.soc_sensor || this._config.entity);
    });

    this.shadowRoot.getElementById("click-status")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.power_sensor || this._config.entity);
    });

    this.shadowRoot.getElementById("click-target")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.entity);
    });

    this.shadowRoot.getElementById("click-upper")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.upper_temp_sensor);
    });

    this.shadowRoot.getElementById("click-lower")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.lower_temp_sensor);
    });

    this.shadowRoot.getElementById("click-shower")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.soc_sensor);
    });

    this.shadowRoot.getElementById("click-auto")?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.automation_entity);
    });

    this.shadowRoot.getElementById("btn-boost")?.addEventListener("click", () => {
      this._callService("climate.set_temperature", {
        entity_id: this._config.entity,
        temperature: 140
      });
    });

    this.shadowRoot.getElementById("btn-reset")?.addEventListener("click", () => {
      this._callService("climate.set_temperature", {
        entity_id: this._config.entity,
        temperature: 120
      });
    });
  }

  _updateContent() {
    if (!this._hass || !this._config || !this._elements.title) return;

    const climateEntity = this._hass.states[this._config.entity];
    const powerEntity = this._config.power_sensor ? this._hass.states[this._config.power_sensor] : null;
    const socEntity = this._config.soc_sensor ? this._hass.states[this._config.soc_sensor] : null;
    const upperEntity = this._config.upper_temp_sensor ? this._hass.states[this._config.upper_temp_sensor] : null;
    const lowerEntity = this._config.lower_temp_sensor ? this._hass.states[this._config.lower_temp_sensor] : null;
    const autoEntity = this._config.automation_entity ? this._hass.states[this._config.automation_entity] : null;

    // Update Title
    this._elements.title.textContent = this._config.title || "♨️ Heat Pump Water Heater";

    // Power-based active state detection:
    let statusText = "Idle";
    let statusColor = "inherit";

    if (powerEntity && !isNaN(parseFloat(powerEntity.state))) {
      const pwr = parseFloat(powerEntity.state);
      if (pwr < 50) {
        statusText = "Idle";
        statusColor = "inherit";
      } else if (pwr < 1000) {
        statusText = "Heat Pump";
        statusColor = "#4caf50";
      } else {
        statusText = "⚡ Element";
        statusColor = "#f44336";
      }
    } else if (climateEntity) {
      const hvacAction = climateEntity.attributes?.hvac_action;
      if (hvacAction === "heating") {
        statusText = "Heating";
        statusColor = "#4caf50";
      } else if (hvacAction === "idle") {
        statusText = "Idle";
      } else if (climateEntity.attributes?.preset_mode) {
        statusText = climateEntity.attributes.preset_mode;
      } else {
        statusText = climateEntity.state === "heat" ? "Idle" : climateEntity.state;
      }
    }

    this._elements.statusVal.textContent = statusText;
    this._elements.statusVal.style.color = statusColor;

    // Target Temperature
    const targetTemp = climateEntity?.attributes?.temperature !== undefined ? `${climateEntity.attributes.temperature}°` : "--";
    this._elements.targetVal.textContent = targetTemp;

    // Automation activity text
    let autoText = "⚡ Automation: Active & monitoring";
    if (autoEntity && autoEntity.attributes && autoEntity.attributes.last_triggered) {
      const last = new Date(autoEntity.attributes.last_triggered);
      const diffMins = Math.round((Date.now() - last.getTime()) / 60000);
      if (diffMins < 60) {
        autoText = `⚡ Last Cycle: ${Math.max(diffMins, 1)} min ago`;
      } else {
        const diffHours = Math.round(diffMins / 60);
        autoText = `⚡ Last Cycle: ${diffHours} hr ago`;
      }
    }
    this._elements.autoText.textContent = autoText;

    // SoC Gauge
    let socVal = 100;
    let socText = "--%";
    if (socEntity && !isNaN(parseFloat(socEntity.state))) {
      socVal = parseFloat(socEntity.state);
      socText = `${Math.round(socVal)}%`;
    }

    let gaugeColor = "#4caf50";
    if (socVal < 60) {
      gaugeColor = "#f44336";
    } else if (socVal < 90) {
      gaugeColor = "#ff9800";
    }

    const normalizedPercent = Math.min(Math.max((socVal / 135) * 100, 0), 100);
    const strokeDash = `${(normalizedPercent * 188.5) / 100} 188.5`;

    this._elements.socMeter.setAttribute("stroke-dasharray", strokeDash);
    this._elements.socMeter.style.stroke = gaugeColor;
    this._elements.socLabel.textContent = socText;

    // Temperatures & Shower Buffer
    this._elements.upperVal.textContent = upperEntity ? `${Math.round(parseFloat(upperEntity.state))}°` : "--";
    this._elements.lowerVal.textContent = lowerEntity ? `${Math.round(parseFloat(lowerEntity.state))}°` : "--";

    // Shower Buffer (Gallons or Minutes)
    const showMinutes = this._config.shower_display !== "gallons";
    let showerValStr = "--";
    let showerTooltip = "Click to view Shower Buffer details";

    if (socEntity && socEntity.attributes) {
      let gal = socEntity.attributes.usable_shower_gallons_est;
      let min = socEntity.attributes.usable_shower_minutes_est;

      // Graceful fallback if only one attribute is present
      if (min === undefined && gal !== undefined) {
        min = Math.round(gal / 2.0);
      } else if (gal === undefined && min !== undefined) {
        gal = Math.round(min * 2.0);
      }

      if (showMinutes) {
        showerValStr = min !== undefined ? `${Math.round(min)} min` : "--";
        if (gal !== undefined) {
          showerTooltip = `Shower Buffer: ~${Math.round(min)} min (approx. ${Math.round(gal)} gal @ 2.0 GPM)`;
        }
      } else {
        showerValStr = gal !== undefined ? `${Math.round(gal)} gal` : "--";
        if (min !== undefined) {
          showerTooltip = `Shower Buffer: ~${Math.round(gal)} gal (approx. ${Math.round(min)} min @ 2.0 GPM)`;
        }
      }
    }

    this._elements.showerVal.textContent = showerValStr;
    if (this._elements.showerItem) {
      this._elements.showerItem.title = showerTooltip;
    }
  }
}

// Register custom element and expose to Home Assistant card picker
if (!customElements.get("hpwh-card")) {
  customElements.define("hpwh-card", HpwhCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "hpwh-card",
    name: "Heat Pump Water Heater Card",
    description: "A compact dashboard card for Heat Pump Water Heaters with SoC, status, temperatures, and boost controls.",
    preview: true,
    documentationURL: "https://github.com/ccma14/homeassistant-toolbox/tree/main/hpwh"
  });
}
