/**
 * Heat Pump Water Heater Custom Lovelace Card
 * Repository: https://github.com/ccma14/homeassistant-toolbox
 * License: Apache 2.0
 */

class HpwhCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  setConfig(config) {
    if (!config.entity) {
      throw new Error("Please define a water heater climate entity.");
    }
    this._config = {
      title: "♨️ Heat Pump Water Heater",
      ...config
    };
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
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
          name: "title",
          selector: { text: {} }
        }
      ]
    };
  }

  static getStubConfig() {
    return {
      title: "♨️ Heat Pump Water Heater",
      entity: "climate.water_heater",
      soc_sensor: "sensor.water_heater_state_of_charge",
      upper_temp_sensor: "sensor.water_heater_upper_tank_temperature",
      lower_temp_sensor: "sensor.water_heater_lower_tank_temperature"
    };
  }

  getCardSize() {
    return 3;
  }

  _callService(service, serviceData) {
    if (!this._hass) return;
    const [domain, action] = service.split(".");
    this._hass.callService(domain, action, serviceData);
  }

  _render() {
    if (!this._hass || !this._config) return;

    const climateEntity = this._hass.states[this._config.entity];
    const socEntity = this._config.soc_sensor ? this._hass.states[this._config.soc_sensor] : null;
    const upperEntity = this._config.upper_temp_sensor ? this._hass.states[this._config.upper_temp_sensor] : null;
    const lowerEntity = this._config.lower_temp_sensor ? this._hass.states[this._config.lower_temp_sensor] : null;

    const title = this._config.title || "♨️ Heat Pump Water Heater";
    const climateState = climateEntity ? climateEntity.state : "unavailable";
    const hvacAction = climateEntity?.attributes?.hvac_action || "";
    const targetTemp = climateEntity?.attributes?.temperature ? `${climateEntity.attributes.temperature}°` : "--";

    // Format SoC
    let socVal = 100;
    let socText = "--%";
    if (socEntity && !isNaN(parseFloat(socEntity.state))) {
      socVal = parseFloat(socEntity.state);
      socText = `${Math.round(socVal)}%`;
    }

    // Color logic for SoC gauge
    let gaugeColor = "#4caf50"; // Green
    if (socVal < 60) {
      gaugeColor = "#f44336"; // Red
    } else if (socVal < 90) {
      gaugeColor = "#ff9800"; // Yellow
    }

    // Shower buffer gallons
    let showerGal = "--";
    if (socEntity && socEntity.attributes && socEntity.attributes.usable_shower_gallons_est !== undefined) {
      showerGal = `${Math.round(socEntity.attributes.usable_shower_gallons_est)} gal`;
    }

    const upperTemp = upperEntity ? `${Math.round(parseFloat(upperEntity.state))}°` : "--";
    const lowerTemp = lowerEntity ? `${Math.round(parseFloat(lowerEntity.state))}°` : "--";

    // Progress percentage for circular dial (0 to 135% scaled to 0-100% of circle)
    const normalizedPercent = Math.min(Math.max((socVal / 135) * 100, 0), 100);
    const strokeDash = `${(normalizedPercent * 188.5) / 100} 188.5`;

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
          stroke: ${gaugeColor};
          stroke-width: 6;
          stroke-linecap: round;
          transition: stroke-dasharray 0.5s ease;
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
        }
        .pill-label {
          font-size: 0.8rem;
          opacity: 0.7;
        }
        .pill-value {
          font-size: 0.95rem;
          font-weight: 600;
          text-transform: capitalize;
        }
        .glance-row {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          background: rgba(255, 255, 255, 0.04);
          border-radius: 10px;
          padding: 10px 8px;
          text-align: center;
          margin-bottom: 14px;
        }
        .glance-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 2px;
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
          <span>${title}</span>
        </div>

        <div class="top-row">
          <div class="soc-container">
            <div style="position: relative; display: flex; align-items: center; justify-content: center;">
              <svg class="soc-svg" viewBox="0 0 70 70">
                <circle class="soc-bg" cx="35" cy="35" r="30"></circle>
                <circle class="soc-meter" cx="35" cy="35" r="30" stroke-dasharray="${strokeDash}"></circle>
              </svg>
              <div class="soc-label">${socText}</div>
            </div>
            <div class="soc-sub">Thermal Storage</div>
          </div>

          <div class="status-stack">
            <div class="pill">
              <span class="pill-label">HPWH Status</span>
              <span class="pill-value">${hvacAction ? hvacAction : climateState}</span>
            </div>
            <div class="pill">
              <span class="pill-label">Target Setpoint</span>
              <span class="pill-value">${targetTemp}</span>
            </div>
          </div>
        </div>

        <div class="glance-row">
          <div class="glance-item">
            <span class="glance-sub">Upper Tank</span>
            <span class="glance-val">${upperTemp}</span>
          </div>
          <div class="glance-item">
            <span class="glance-sub">Lower Tank</span>
            <span class="glance-val">${lowerTemp}</span>
          </div>
          <div class="glance-item">
            <span class="glance-sub">Shower Buffer</span>
            <span class="glance-val">${showerGal}</span>
          </div>
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
