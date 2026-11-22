/**
 * Heat Pump Water Heater Custom Lovelace Card
 * Repository: https://github.com/ccma14/homeassistant-toolbox
 * License: Apache 2.0
 */

const CARD_VERSION = "1.2.0";

console.info(
  `%c HPWH-CARD %c v${CARD_VERSION} `,
  "color: white; background: #0288d1; font-weight: 700; border-radius: 3px 0 0 3px;",
  "color: #0288d1; background: #e1f5fe; font-weight: 700; border-radius: 0 3px 3px 0;"
);

class HpwhCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._initialized = false;
    this._elements = {};
    this._displayUnit = null;
    this._latestLog = null;
    this._lastLogFetch = 0;
    this._prevLastTriggered = null;
    this._prevTargetTemp = null;
    this._hasFetchedLogbook = false;
    this._fetchRequestId = 0;
    this._ticker = null;
    this._retryTimeout = null;
  }

  connectedCallback() {
    if (!this._ticker) {
      this._ticker = setInterval(() => {
        const autoEntity = this._config?.automation_entity ? this._hass?.states[this._config.automation_entity] : null;
        this._updateAutoText(autoEntity);
        if (Date.now() - this._lastLogFetch > 300000) {
          this._fetchLogbook();
        }
      }, 60000);
    }
  }

  disconnectedCallback() {
    if (this._ticker) {
      clearInterval(this._ticker);
      this._ticker = null;
    }
    if (this._retryTimeout) {
      clearTimeout(this._retryTimeout);
      this._retryTimeout = null;
    }
  }

  setConfig(config) {
    if (!config.entity) {
      throw new Error("Please define a water heater climate entity.");
    }
    // If entity or automation_entity changed, reset stale logbook & trigger tracking
    if (this._config && (this._config.entity !== config.entity || this._config.automation_entity !== config.automation_entity)) {
      this._latestLog = null;
      this._lastLogFetch = 0;
      this._prevLastTriggered = null;
      this._prevTargetTemp = null;
      this._hasFetchedLogbook = false;
    }
    this._config = {
      title: "♨️ Heat Pump Water Heater",
      shower_display: "minutes",
      boost_temperature: 140,
      reset_temperature: 120,
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
          name: "shower_minutes_sensor",
          selector: { entity: { domain: "sensor" } }
        },
        {
          name: "shower_gallons_sensor",
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
          name: "boost_temperature",
          default: 140,
          selector: { number: { min: 60, max: 160, step: 1, mode: "box" } }
        },
        {
          name: "reset_temperature",
          default: 120,
          selector: { number: { min: 60, max: 140, step: 1, mode: "box" } }
        },
        {
          name: "title",
          selector: { text: {} }
        }
      ],
      computeLabel: (schema) => {
        const labels = {
          entity: "Water Heater Climate Entity",
          power_sensor: "Power Sensor (for operating state)",
          soc_sensor: "State of Charge Sensor",
          shower_minutes_sensor: "Shower Minutes Sensor",
          shower_gallons_sensor: "Shower Gallons Sensor",
          upper_temp_sensor: "Upper Tank Temperature Sensor",
          lower_temp_sensor: "Lower Tank Temperature Sensor",
          automation_entity: "HPWH Automation Entity",
          shower_display: "Default Shower Buffer Display",
          boost_temperature: "Manual Boost Target (°F)",
          reset_temperature: "Manual Reset Target (°F)",
          title: "Card Title"
        };
        return labels[schema.name] || schema.name;
      },
      computeHelper: (schema) => {
        const helpers = {
          entity: "The climate entity controlling your heat pump water heater",
          power_sensor: "Monitors compressor / element wattage (optional)",
          soc_sensor: "Calculated 0–100% tank thermal reserve sensor",
          shower_display: "Initial display metric on card load (minutes or gallons)",
          boost_temperature: "Target temperature set when clicking Boost button",
          reset_temperature: "Target temperature set when clicking Reset button",
          automation_entity: "The automation blueprint instance for status tracking"
        };
        return helpers[schema.name] || "";
      }
    };
  }

  static getGridOptions() {
    return {
      columns: 12,
      rows: 4,
      min_columns: 6,
      min_rows: 3
    };
  }

  static getStubConfig(hass) {
    let climateEntity = "climate.water_heater";
    let powerSensor = "sensor.water_heater_power";
    let socSensor = "sensor.water_heater_state_of_charge";
    let minSensor = "sensor.water_heater_shower_minutes";
    let galSensor = "sensor.water_heater_shower_gallons";
    let upperSensor = "sensor.water_heater_upper_tank_temperature";
    let lowerSensor = "sensor.water_heater_lower_tank_temperature";
    let autoEntity = "automation.solar_stratification_heat_pump_water_heater_manager";

    if (hass && hass.states) {
      const entities = Object.keys(hass.states);
      const climateMatch = entities.find(e => e.startsWith("climate.") && (e.includes("water_heater") || e.includes("hpwh") || e.includes("econet") || e.includes("heatpump") || e.includes("heat_pump"))) ||
        entities.find(e => e.startsWith("climate."));
      if (climateMatch) climateEntity = climateMatch;

      const socMatch = entities.find(e => e.startsWith("sensor.") && (e.includes("state_of_charge") || e.includes("soc")));
      if (socMatch) socSensor = socMatch;

      const powerMatch = entities.find(e => e.startsWith("sensor.") && (e.includes("power") || e.includes("watts")) && (e.includes("water_heater") || e.includes("hpwh") || e.includes("heatpump") || e.includes("heat_pump")));
      if (powerMatch) powerSensor = powerMatch;

      const upperMatch = entities.find(e => e.startsWith("sensor.") && e.includes("upper") && (e.includes("temp") || e.includes("tank")));
      if (upperMatch) upperSensor = upperMatch;

      const lowerMatch = entities.find(e => e.startsWith("sensor.") && e.includes("lower") && (e.includes("temp") || e.includes("tank")));
      if (lowerMatch) lowerSensor = lowerMatch;

      const minMatch = entities.find(e => e.startsWith("sensor.") && e.includes("shower") && e.includes("minutes"));
      if (minMatch) minSensor = minMatch;

      const galMatch = entities.find(e => e.startsWith("sensor.") && e.includes("shower") && e.includes("gallons"));
      if (galMatch) galSensor = galMatch;

      const autoMatch = entities.find(e => e.startsWith("automation.") && (e.includes("hpwh") || e.includes("water_heater") || e.includes("solar")));
      if (autoMatch) autoEntity = autoMatch;
    }

    return {
      title: "♨️ Heat Pump Water Heater",
      shower_display: "minutes",
      entity: climateEntity,
      power_sensor: powerSensor,
      soc_sensor: socSensor,
      shower_minutes_sensor: minSensor,
      shower_gallons_sensor: galSensor,
      upper_temp_sensor: upperSensor,
      lower_temp_sensor: lowerSensor,
      automation_entity: autoEntity,
      boost_temperature: 140,
      reset_temperature: 120
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

  _getShowerSensorIds() {
    return {
      minutes: this._config?.shower_minutes_sensor || "sensor.water_heater_shower_minutes",
      gallons: this._config?.shower_gallons_sensor || "sensor.water_heater_shower_gallons"
    };
  }

  _getShowerMoreInfoEntity(showMinutes) {
    const { minutes, gallons } = this._getShowerSensorIds();
    if (showMinutes) {
      return this._hass?.states[minutes] ? minutes : (this._config?.soc_sensor || this._config?.entity);
    }
    return this._hass?.states[gallons] ? gallons : (this._hass?.states[minutes] ? minutes : (this._config?.soc_sensor || this._config?.entity));
  }

  _initDOM() {
    this.shadowRoot.innerHTML = `
      <style>
        ha-card {
          padding: 16px;
          background: var(--ha-card-background, var(--card-background-color, white));
          border-radius: var(--ha-card-border-radius, 12px);
          border-width: var(--ha-card-border-width, 1px);
          border-style: var(--ha-card-border-style, solid);
          border-color: var(--ha-card-border-color, var(--divider-color, rgba(127, 127, 127, 0.15)));
          box-shadow: var(--ha-card-box-shadow, none);
          font-family: var(--ha-card-font-family, inherit);
          color: var(--primary-text-color);
          box-sizing: border-box;
          user-select: none;
          min-height: 290px;
        }
        .header {
          font-size: 1.15rem;
          font-weight: 600;
          margin-bottom: 14px;
          color: var(--primary-text-color);
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
          background: var(--secondary-background-color, rgba(127, 127, 127, 0.08));
          border: 1px solid var(--divider-color, rgba(127, 127, 127, 0.12));
          border-radius: 10px;
          padding: 8px;
          cursor: pointer;
          transition: background 0.2s, transform 0.1s, border-color 0.2s;
        }
        .soc-container:hover {
          background: var(--ha-card-background-hover, var(--divider-color, rgba(127, 127, 127, 0.16)));
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
          stroke: var(--divider-color, rgba(127, 127, 127, 0.25));
          stroke-width: 6;
        }
        .soc-meter {
          fill: none;
          stroke: var(--success-color, #4caf50);
          stroke-width: 6;
          stroke-linecap: round;
          transition: stroke-dasharray 0.5s ease, stroke 0.3s;
        }
        .soc-label {
          position: absolute;
          font-size: 1.25rem;
          font-weight: 700;
          text-align: center;
          color: var(--primary-text-color);
        }
        .soc-sub {
          font-size: 0.72rem;
          color: var(--secondary-text-color);
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
          background: var(--secondary-background-color, rgba(127, 127, 127, 0.08));
          border: 1px solid var(--divider-color, rgba(127, 127, 127, 0.12));
          border-radius: 10px;
          padding: 8px 12px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          cursor: pointer;
          transition: background 0.2s, transform 0.1s, border-color 0.2s;
        }
        .pill:hover {
          background: var(--ha-card-background-hover, var(--divider-color, rgba(127, 127, 127, 0.16)));
        }
        .pill:active {
          transform: scale(0.98);
        }
        .pill-label {
          font-size: 0.8rem;
          color: var(--secondary-text-color);
        }
        .pill-value {
          font-size: 0.95rem;
          font-weight: 600;
          color: var(--primary-text-color);
          text-transform: capitalize;
          display: flex;
          align-items: center;
          gap: 4px;
        }
        .glance-row {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          background: var(--secondary-background-color, rgba(127, 127, 127, 0.08));
          border: 1px solid var(--divider-color, rgba(127, 127, 127, 0.12));
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
          background: var(--ha-card-background-hover, var(--divider-color, rgba(127, 127, 127, 0.16)));
        }
        .glance-item:active {
          transform: scale(0.96);
        }
        .glance-item:not(:last-child) {
          border-right: 1px solid var(--divider-color, rgba(127, 127, 127, 0.15));
        }
        .glance-sub {
          font-size: 0.72rem;
          color: var(--secondary-text-color);
        }
        .glance-val {
          font-size: 1rem;
          font-weight: 600;
          color: var(--primary-text-color);
        }
        .auto-row {
          background: var(--secondary-background-color, rgba(127, 127, 127, 0.05));
          border: 1px solid var(--divider-color, rgba(127, 127, 127, 0.1));
          border-radius: 8px;
          padding: 6px 10px;
          font-size: 0.78rem;
          color: var(--secondary-text-color);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 12px;
          cursor: pointer;
          transition: background 0.2s, color 0.2s, border-color 0.2s;
          overflow: hidden;
        }
        .auto-row span {
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .auto-row:hover {
          background: var(--ha-card-background-hover, var(--divider-color, rgba(127, 127, 127, 0.16)));
          color: var(--primary-text-color);
        }
        .actions-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
        }
        .btn {
          background: var(--secondary-background-color, rgba(127, 127, 127, 0.08));
          border: 1px solid var(--divider-color, rgba(127, 127, 127, 0.2));
          border-radius: 8px;
          padding: 10px;
          font-size: 0.88rem;
          font-weight: 600;
          color: var(--primary-text-color);
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
          transition: background 0.2s, transform 0.1s, border-color 0.2s;
        }
        .btn:hover {
          background: var(--ha-card-background-hover, var(--divider-color, rgba(127, 127, 127, 0.22)));
        }
        .btn:active {
          transform: scale(0.98);
        }
        .btn-boost {
          border-color: var(--warning-color, rgba(255, 152, 0, 0.5));
        }
        .btn-boost:hover {
          background: rgba(255, 152, 0, 0.12);
        }
        .soc-container:focus-visible,
        .pill:focus-visible,
        .glance-item:focus-visible,
        .auto-row:focus-visible,
        .btn:focus-visible {
          outline: 2px solid var(--primary-color, #03a9f4);
          outline-offset: 2px;
        }
      </style>

      <ha-card>
        <div class="header">
          <span id="card-title">♨️ Heat Pump Water Heater</span>
        </div>

        <div class="top-row">
          <div class="soc-container" id="click-soc" role="button" tabindex="0" aria-label="Water heater state of charge. Click to view history." title="Click to view State of Charge history">
            <div style="position: relative; display: flex; align-items: center; justify-content: center;">
              <svg class="soc-svg" viewBox="0 0 70 70">
                <circle class="soc-bg" cx="35" cy="35" r="30"></circle>
                <circle class="soc-meter" id="soc-meter" cx="35" cy="35" r="30" stroke-dasharray="0 188.5"></circle>
              </svg>
              <div class="soc-label" id="soc-label">--%</div>
            </div>
            <div class="soc-sub" id="soc-sub">Thermal Storage</div>
          </div>

          <div class="status-stack">
            <div class="pill" id="click-status" role="button" tabindex="0" aria-label="Operating status. Click to view power history." title="Click to view power / status history">
              <span class="pill-label">HPWH Status</span>
              <span class="pill-value" id="status-val">Idle</span>
            </div>
            <div class="pill" id="click-target" role="button" tabindex="0" aria-label="Target setpoint. Click to adjust temperature." title="Click to adjust water heater temperature">
              <span class="pill-label">Target Setpoint</span>
              <span class="pill-value" id="target-val">--</span>
            </div>
          </div>
        </div>

        <div class="glance-row">
          <div class="glance-item" id="click-upper" role="button" tabindex="0" aria-label="Upper tank temperature. Click to view history." title="Click to view Upper Tank history">
            <span class="glance-sub">Upper Tank</span>
            <span class="glance-val" id="upper-val">--</span>
          </div>
          <div class="glance-item" id="click-lower" role="button" tabindex="0" aria-label="Lower tank temperature. Click to view history." title="Click to view Lower Tank history">
            <span class="glance-sub">Lower Tank</span>
            <span class="glance-val" id="lower-val">--</span>
          </div>
          <div class="glance-item" id="click-shower" role="button" tabindex="0" aria-label="Shower buffer. Click to view history, double-click to toggle units." title="Click to view Shower Buffer history">
            <span class="glance-sub">Shower Buffer</span>
            <span class="glance-val" id="shower-val">--</span>
          </div>
        </div>

        <div class="auto-row" id="click-auto" role="button" tabindex="0" aria-label="Automation status. Click to view automation history." title="Click to view automation history">
          <span id="auto-text">⚡ Automation: Active & monitoring</span>
        </div>

        <div class="actions-row">
          <button class="btn btn-boost" id="btn-boost">
            ☀️ Boost
          </button>
          <button class="btn" id="btn-reset">
            🔄 Reset
          </button>
        </div>
      </ha-card>
    `;

    // Cache elements for high-performance updates without DOM recreation
    this._elements = {
      title: this.shadowRoot.getElementById("card-title"),
      socMeter: this.shadowRoot.getElementById("soc-meter"),
      socLabel: this.shadowRoot.getElementById("soc-label"),
      socSub: this.shadowRoot.getElementById("soc-sub"),
      statusVal: this.shadowRoot.getElementById("status-val"),
      targetVal: this.shadowRoot.getElementById("target-val"),
      upperVal: this.shadowRoot.getElementById("upper-val"),
      lowerVal: this.shadowRoot.getElementById("lower-val"),
      showerVal: this.shadowRoot.getElementById("shower-val"),
      showerItem: this.shadowRoot.getElementById("click-shower"),
      autoRow: this.shadowRoot.getElementById("click-auto"),
      autoText: this.shadowRoot.getElementById("auto-text"),
      btnBoost: this.shadowRoot.getElementById("btn-boost"),
      btnReset: this.shadowRoot.getElementById("btn-reset")
    };

    // Keyboard accessibility helper for interactive div elements
    const addKeyHandler = (el) => {
      el?.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          el.click();
        }
      });
    };

    // Attach click and keyboard events once
    const socEl = this.shadowRoot.getElementById("click-soc");
    socEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.soc_sensor || this._config.entity);
    });
    addKeyHandler(socEl);

    const statusEl = this.shadowRoot.getElementById("click-status");
    statusEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.power_sensor || this._config.entity);
    });
    addKeyHandler(statusEl);

    const targetEl = this.shadowRoot.getElementById("click-target");
    targetEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.entity);
    });
    addKeyHandler(targetEl);

    const upperEl = this.shadowRoot.getElementById("click-upper");
    upperEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.upper_temp_sensor);
    });
    addKeyHandler(upperEl);

    const lowerEl = this.shadowRoot.getElementById("click-lower");
    lowerEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.lower_temp_sensor);
    });
    addKeyHandler(lowerEl);

    let showerClickTimeout = null;
    const showerItem = this.shadowRoot.getElementById("click-shower");
    showerItem?.addEventListener("click", (e) => {
      e.stopPropagation();
      if (showerClickTimeout) {
        // Double-click detected: cancel more-info dialog and toggle units
        clearTimeout(showerClickTimeout);
        showerClickTimeout = null;
        const activeUnit = this._displayUnit || this._config.shower_display || "minutes";
        this._displayUnit = activeUnit === "minutes" ? "gallons" : "minutes";
        this._updateContent();
      } else {
        showerClickTimeout = setTimeout(() => {
          showerClickTimeout = null;
          const activeUnit = this._displayUnit || this._config.shower_display || "minutes";
          const showMinutes = activeUnit !== "gallons";
          this._fireMoreInfo(this._getShowerMoreInfoEntity(showMinutes));
        }, 250);
      }
    });
    addKeyHandler(showerItem);

    const autoEl = this.shadowRoot.getElementById("click-auto");
    autoEl?.addEventListener("click", () => {
      this._fireMoreInfo(this._config.automation_entity);
    });
    addKeyHandler(autoEl);

    this.shadowRoot.getElementById("btn-boost")?.addEventListener("click", () => {
      const target = this._config.boost_temperature ?? 140;
      if (!window.confirm(`Boost water heater to ${target}°?`)) return;
      this._callService("climate.set_temperature", {
        entity_id: this._config.entity,
        temperature: target
      });
    });

    this.shadowRoot.getElementById("btn-reset")?.addEventListener("click", () => {
      const target = this._config.reset_temperature ?? 120;
      if (!window.confirm(`Reset water heater to ${target}°?`)) return;
      this._callService("climate.set_temperature", {
        entity_id: this._config.entity,
        temperature: target
      });
    });
  }

  async _fetchLogbook(force = false) {
    if (!this._hass || !this._config) return;
    const now = Date.now();
    if (!force && now - this._lastLogFetch < 10000) return;
    this._lastLogFetch = now;
    this._hasFetchedLogbook = true;
    const reqId = ++this._fetchRequestId;

    const entities = [];
    if (this._config.entity) entities.push(this._config.entity);
    if (this._config.automation_entity) entities.push(this._config.automation_entity);
    if (!entities.length) return;

    // Look back up to 48 hours for the most recent logbook entry
    const startTime = new Date(now - 48 * 3600 * 1000).toISOString();

    try {
      const events = await this._hass.callWS({
        type: "logbook/get_events",
        start_time: startTime,
        entity_ids: entities
      });

      // Ignore response if a newer fetch request has already been issued
      if (reqId !== this._fetchRequestId) return;

      if (Array.isArray(events) && events.length > 0) {
        // Filter strictly for HPWH Manager events with a message
        const hpwhEvents = events.filter(e =>
          e.name === "HPWH Manager" && e.message
        );

        const latest = hpwhEvents.length > 0 ? hpwhEvents[hpwhEvents.length - 1] : null;

        if (latest && latest.message) {
          let whenDate;
          if (typeof latest.when === "number") {
            whenDate = new Date(latest.when < 1e11 ? latest.when * 1000 : latest.when);
          } else {
            whenDate = new Date(latest.when);
          }

          this._latestLog = {
            message: latest.message,
            when: whenDate
          };
          const autoEntity = this._config.automation_entity ? this._hass.states[this._config.automation_entity] : null;
          this._updateAutoText(autoEntity);
        }
      }
    } catch (err) {
      console.warn("hpwh-card: logbook fetch error", err);
    }
  }

  _updateAutoText(autoEntity) {
    if (!this._elements.autoText) return;

    if (this._latestLog && this._latestLog.message) {
      const diffMins = Math.round((Date.now() - this._latestLog.when.getTime()) / 60000);
      let timeStr = "just now";
      if (diffMins >= 60) {
        const diffHours = Math.round(diffMins / 60);
        timeStr = `${diffHours} hr ago`;
      } else if (diffMins >= 1) {
        timeStr = `${diffMins} min ago`;
      }

      const fullText = `⚡ ${this._latestLog.message} • ${timeStr}`;
      this._elements.autoText.textContent = fullText;
      if (this._elements.autoRow) {
        this._elements.autoRow.title = `${this._latestLog.message} (${this._latestLog.when.toLocaleTimeString()}) — Click to view automation history`;
      }
    } else if (autoEntity && autoEntity.attributes && autoEntity.attributes.last_triggered) {
      const last = new Date(autoEntity.attributes.last_triggered);
      const diffMins = Math.round((Date.now() - last.getTime()) / 60000);
      let timeStr = diffMins < 60 ? `${Math.max(diffMins, 1)} min ago` : `${Math.round(diffMins / 60)} hr ago`;
      this._elements.autoText.textContent = `⚡ Last Cycle: ${timeStr}`;
    } else {
      this._elements.autoText.textContent = "⚡ Automation: Active & monitoring";
    }
  }

  _updateContent() {
    if (!this._hass || !this._config || !this._elements.title) return;

    const climateEntity = this._hass.states[this._config.entity];
    const powerEntity = this._config.power_sensor ? this._hass.states[this._config.power_sensor] : null;
    const socEntity = this._config.soc_sensor ? this._hass.states[this._config.soc_sensor] : null;
    const upperEntity = this._config.upper_temp_sensor ? this._hass.states[this._config.upper_temp_sensor] : null;
    const lowerEntity = this._config.lower_temp_sensor ? this._hass.states[this._config.lower_temp_sensor] : null;
    const autoEntity = this._config.automation_entity ? this._hass.states[this._config.automation_entity] : null;
    const { minutes: minSensorId, gallons: galSensorId } = this._getShowerSensorIds();
    const minEntity = this._hass.states[minSensorId] || null;
    const galEntity = this._hass.states[galSensorId] || null;

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
        statusColor = "var(--success-color, #4caf50)";
      } else {
        statusText = "⚡ Element";
        statusColor = "var(--error-color, #f44336)";
      }
    } else if (climateEntity) {
      const hvacAction = climateEntity.attributes?.hvac_action;
      if (hvacAction === "heating") {
        statusText = "Heating";
        statusColor = "var(--success-color, #4caf50)";
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

    // Action button labels
    const boostTarget = this._config.boost_temperature ?? 140;
    const resetTarget = this._config.reset_temperature ?? 120;
    if (this._elements.btnBoost) {
      this._elements.btnBoost.textContent = `☀️ Boost ${boostTarget}°`;
    }
    if (this._elements.btnReset) {
      this._elements.btnReset.textContent = `🔄 Reset ${resetTarget}°`;
    }

    // Automation activity text & live logbook fetch
    const lastTriggered = autoEntity?.attributes?.last_triggered;
    const curTargetTemp = climateEntity?.attributes?.temperature;
    const isInitial = !this._hasFetchedLogbook;
    const shouldFetch = isInitial ||
      (lastTriggered && lastTriggered !== this._prevLastTriggered) ||
      (curTargetTemp !== undefined && curTargetTemp !== this._prevTargetTemp);

    if (shouldFetch) {
      this._prevLastTriggered = lastTriggered;
      this._prevTargetTemp = curTargetTemp;
      this._fetchLogbook();
      // Retry in 2s to handle database write latency (live state/trigger updates only, not initial load)
      if (!isInitial) {
        clearTimeout(this._retryTimeout);
        this._retryTimeout = setTimeout(() => this._fetchLogbook(true), 2000);
      }
    }
    this._updateAutoText(autoEntity);

    // SoC Gauge & Boost
    let hasSoc = false;
    let socVal = 0;
    let socText = "--%";
    let boostVal = 0;

    if (socEntity && !isNaN(parseFloat(socEntity.state))) {
      hasSoc = true;
      socVal = parseFloat(socEntity.state);
      // Cap nominal state strictly at 100%
      const displaySoc = Math.min(Math.round(socVal), 100);
      socText = `${displaySoc}%`;

      // Check for solar boost surplus
      if (socEntity.attributes && socEntity.attributes.solar_boost !== undefined) {
        boostVal = Math.round(parseFloat(socEntity.attributes.solar_boost));
      } else if (socEntity.attributes && socEntity.attributes.raw_soc !== undefined) {
        boostVal = Math.max(Math.round(parseFloat(socEntity.attributes.raw_soc) - 100), 0);
      } else if (socVal > 100) {
        boostVal = Math.round(socVal - 100);
      }
    }

    let gaugeColor = "var(--state-icon-color, #757575)"; // Default neutral gray if unavailable
    if (hasSoc) {
      if (socVal < 60) {
        gaugeColor = "var(--error-color, #f44336)";
      } else if (socVal < 90) {
        gaugeColor = "var(--warning-color, #ff9800)";
      } else if (boostVal > 0) {
        gaugeColor = "var(--state-solar-color, #ffb300)"; // Solar Gold
      } else {
        gaugeColor = "var(--success-color, #4caf50)";
      }
    }

    const normalizedPercent = hasSoc ? Math.min(Math.max(socVal, 0), 100) : 0;
    const strokeDash = `${(normalizedPercent * 188.5) / 100} 188.5`;

    this._elements.socMeter.setAttribute("stroke-dasharray", strokeDash);
    this._elements.socMeter.style.stroke = gaugeColor;
    this._elements.socLabel.textContent = socText;

    if (this._elements.socSub) {
      if (boostVal > 0) {
        this._elements.socSub.textContent = `+${boostVal}% Solar Boost`;
        this._elements.socSub.style.color = "var(--state-solar-color, #ffb300)";
        this._elements.socSub.style.fontWeight = "600";
      } else {
        this._elements.socSub.textContent = "Thermal Storage";
        this._elements.socSub.style.color = "";
        this._elements.socSub.style.fontWeight = "";
      }
    }

    // Temperatures & Shower Buffer
    const upperNum = upperEntity && !isNaN(parseFloat(upperEntity.state)) ? Math.round(parseFloat(upperEntity.state)) : null;
    const lowerNum = lowerEntity && !isNaN(parseFloat(lowerEntity.state)) ? Math.round(parseFloat(lowerEntity.state)) : null;

    this._elements.upperVal.textContent = upperNum !== null ? `${upperNum}°` : "--";
    this._elements.lowerVal.textContent = lowerNum !== null ? `${lowerNum}°` : "--";

    // Shower Buffer (Gallons or Minutes)
    const activeUnit = this._displayUnit || this._config.shower_display || "minutes";
    const showMinutes = activeUnit !== "gallons";
    let showerValStr = "--";
    let showerTooltip = "Click for history graph, double-click to toggle units";

    let min = minEntity && !isNaN(parseFloat(minEntity.state)) ? parseFloat(minEntity.state) : undefined;
    let gal = galEntity && !isNaN(parseFloat(galEntity.state)) ? parseFloat(galEntity.state) : undefined;

    // Graceful fallback if only one unit sensor is available
    if (min === undefined && gal !== undefined) {
      min = Math.round(gal / 2.0);
    } else if (gal === undefined && min !== undefined) {
      gal = Math.round(min * 2.0);
    }

    if (showMinutes) {
      showerValStr = min !== undefined ? `${Math.round(min)} min` : "--";
      if (gal !== undefined) {
        showerTooltip = `Shower Buffer: ~${Math.round(min)} min (approx. ${Math.round(gal)} gal) — Click for minutes history graph, double-click to toggle units`;
      }
    } else {
      showerValStr = gal !== undefined ? `${Math.round(gal)} gal` : "--";
      if (min !== undefined) {
        showerTooltip = `Shower Buffer: ~${Math.round(gal)} gal (approx. ${Math.round(min)} min) — Click for gallons history graph, double-click to toggle units`;
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
