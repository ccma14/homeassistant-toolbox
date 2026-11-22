#!/usr/bin/env python3
"""
Test suite for HPWH template sensors (hpwh/hpwh.yaml & hpwh/templates.yaml).
Tests mathematical formulas and renders the actual Jinja2 templates from hpwh.yaml
with Home Assistant mock environment stubs.
"""

import os
import re
import unittest

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

try:
    import jinja2
    HAS_JINJA = True
except ImportError:
    HAS_JINJA = False

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
HPWH_YAML_PATH = os.path.join(REPO_ROOT, "hpwh/hpwh.yaml")
TEMPLATES_YAML_PATH = os.path.join(REPO_ROOT, "hpwh/templates.yaml")


def compute_hpwh_metrics(upper: float, lower: float, cold_inlet: float = 65.0,
                         target_baseline: float = 120.0, tank_gallons: float = 65.0,
                         shower_temp: float = 105.0, shower_gpm: float = 2.0):
    """
    Python reference implementation of the formulas in hpwh.yaml
    """
    avg_temp = (upper * 0.4) + (lower * 0.6)
    raw_soc = ((avg_temp - cold_inlet) / (target_baseline - cold_inlet)) * 100.0
    soc = min(max(round(raw_soc), 0), 100)
    solar_boost = max(round(raw_soc - 100), 0)

    if avg_temp > cold_inlet:
        total_heat_btu = tank_gallons * 8.33 * (avg_temp - cold_inlet)
        gal_at_105 = total_heat_btu / (8.33 * (shower_temp - cold_inlet))
        shower_gal = max(round(gal_at_105), 0)
    else:
        shower_gal = 0

    shower_min = max(round(shower_gal / shower_gpm), 0)

    return {
        "avg_temp": round(avg_temp, 1),
        "raw_soc": round(raw_soc, 1),
        "soc": soc,
        "solar_boost": solar_boost,
        "shower_gallons": shower_gal,
        "shower_minutes": shower_min
    }


def make_ha_jinja_env(states_map=None, attrs_map=None):
    states_map = states_map or {}
    attrs_map = attrs_map or {}

    def ha_float(val, default=0.0):
        try:
            return float(val)
        except (ValueError, TypeError):
            return float(default)

    def is_number(val):
        try:
            float(val)
            return True
        except (ValueError, TypeError):
            return False

    env = jinja2.Environment()
    env.filters["float"] = ha_float
    env.filters["round"] = lambda val, precision=0: round(float(val), precision) if precision > 0 else int(round(float(val)))
    env.globals["states"] = lambda entity: str(states_map.get(entity, "unavailable"))
    env.globals["has_value"] = lambda entity: entity in states_map and states_map[entity] not in ("unavailable", "unknown", None)
    env.globals["state_attr"] = lambda entity, attr: attrs_map.get(entity, {}).get(attr, None)
    env.globals["is_number"] = is_number
    return env


class TestHpwhTemplates(unittest.TestCase):
    def test_package_files_exist(self):
        self.assertTrue(os.path.isfile(HPWH_YAML_PATH), "hpwh/hpwh.yaml must exist")
        self.assertTrue(os.path.isfile(TEMPLATES_YAML_PATH), "hpwh/templates.yaml must exist")

    def test_availability_guards_present(self):
        """Ensure all sensors have availability blocks to prevent false 100% readings when offline"""
        with open(HPWH_YAML_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("has_value('sensor.water_heater_upper_tank_temperature')", content)
        self.assertIn("has_value('sensor.water_heater_lower_tank_temperature')", content)
        self.assertIn("has_value('sensor.water_heater_shower_gallons')", content)

    def test_device_classes(self):
        """Ensure shower gallons and minutes have correct Home Assistant device classes"""
        with open(HPWH_YAML_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("device_class: volume_storage", content)
        self.assertIn("device_class: duration", content)

    def test_nominal_full_tank(self):
        """At 120°F uniform tank temp, nominal SoC should be exactly 100% with 0% boost"""
        m = compute_hpwh_metrics(upper=120.0, lower=120.0, cold_inlet=65.0, target_baseline=120.0, tank_gallons=65.0)
        self.assertEqual(m["avg_temp"], 120.0)
        self.assertEqual(m["soc"], 100)
        self.assertEqual(m["solar_boost"], 0)
        self.assertEqual(m["shower_gallons"], 89)
        self.assertEqual(m["shower_minutes"], 44)

    def test_solar_boost_overdrive(self):
        """At 140°F uniform solar boost, SoC is capped at 100% and solar_boost tracks surplus"""
        m = compute_hpwh_metrics(upper=140.0, lower=140.0, cold_inlet=65.0, target_baseline=120.0, tank_gallons=65.0)
        self.assertEqual(m["avg_temp"], 140.0)
        self.assertEqual(m["soc"], 100)
        self.assertEqual(m["solar_boost"], 36)
        self.assertEqual(m["shower_gallons"], 122)
        self.assertEqual(m["shower_minutes"], 61)

    def test_stratified_depleted_tank(self):
        """Evening stratification: warm upper layer (110°F), cold lower zone (65°F)"""
        m = compute_hpwh_metrics(upper=110.0, lower=65.0, cold_inlet=65.0, target_baseline=120.0, tank_gallons=65.0)
        self.assertEqual(m["avg_temp"], 83.0)
        self.assertEqual(m["soc"], 33)
        self.assertEqual(m["solar_boost"], 0)
        self.assertEqual(m["shower_gallons"], 29)
        self.assertEqual(m["shower_minutes"], 14)

    def test_cold_below_inlet(self):
        """If incoming water or room temp is below calibration baseline, clamped to 0"""
        m = compute_hpwh_metrics(upper=50.0, lower=50.0, cold_inlet=65.0)
        self.assertEqual(m["soc"], 0)
        self.assertEqual(m["solar_boost"], 0)
        self.assertEqual(m["shower_gallons"], 0)
        self.assertEqual(m["shower_minutes"], 0)

    def test_80_gallon_tank_scaling(self):
        """Validates scaling with larger 80 gallon tank size"""
        m = compute_hpwh_metrics(upper=120.0, lower=120.0, cold_inlet=65.0, tank_gallons=80.0)
        self.assertEqual(m["soc"], 100)
        self.assertEqual(m["shower_gallons"], 110)
        self.assertEqual(m["shower_minutes"], 55)

    def test_real_jinja_rendering(self):
        """Render the actual Jinja2 template strings from hpwh.yaml (T-d)"""
        if not HAS_JINJA:
            self.skipTest("jinja2 module not available; skipping live template rendering test")

        with open(HPWH_YAML_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        # Extract SoC state template
        m_soc = re.search(r"unique_id: water_heater_state_of_charge[\s\S]*?state: >-\s*([\s\S]*?)\n\s+attributes:", content)
        self.assertIsNotNone(m_soc, "Could not extract SoC state template from hpwh.yaml")
        soc_tmpl_str = m_soc.group(1)

        # Extract shower gallons state template
        m_gal = re.search(r"unique_id: water_heater_shower_gallons[\s\S]*?state: >-\s*([\s\S]*?)\n\s+attributes:", content)
        self.assertIsNotNone(m_gal, "Could not extract shower gallons state template from hpwh.yaml")
        gal_tmpl_str = m_gal.group(1)

        # Test case 1: Nominal full tank (120°F upper, 120°F lower)
        env = make_ha_jinja_env(
            states_map={
                "sensor.water_heater_upper_tank_temperature": 120.0,
                "sensor.water_heater_lower_tank_temperature": 120.0,
            },
            attrs_map={
                "sensor.water_heater_state_of_charge": {
                    "cold_inlet_temperature": 65.0,
                    "tank_gallons": 65.0,
                    "target_baseline_temperature": 120.0,
                }
            }
        )

        res_soc = env.from_string(soc_tmpl_str).render().strip()
        self.assertEqual(int(res_soc), 100)

        res_gal = env.from_string(gal_tmpl_str).render().strip()
        self.assertEqual(int(res_gal), 89)

        # Test case 2: Stratified tank (110°F upper, 65°F lower)
        env_strat = make_ha_jinja_env(
            states_map={
                "sensor.water_heater_upper_tank_temperature": 110.0,
                "sensor.water_heater_lower_tank_temperature": 65.0,
            },
            attrs_map={
                "sensor.water_heater_state_of_charge": {
                    "cold_inlet_temperature": 65.0,
                    "tank_gallons": 65.0,
                    "target_baseline_temperature": 120.0,
                }
            }
        )
        res_soc_strat = env_strat.from_string(soc_tmpl_str).render().strip()
        self.assertEqual(int(res_soc_strat), 33)

        res_gal_strat = env_strat.from_string(gal_tmpl_str).render().strip()
        self.assertEqual(int(res_gal_strat), 29)


if __name__ == "__main__":
    unittest.main()
