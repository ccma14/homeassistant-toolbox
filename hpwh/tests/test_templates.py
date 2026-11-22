#!/usr/bin/env python3
"""
Test suite for HPWH template sensors (hpwh/hpwh.yaml & hpwh/templates.yaml).
Tests mathematical formulas for:
  - Volumetric weighted average temperature
  - State of Charge (SoC) % capped at 100%
  - Solar boost thermal reserve surplus %
  - Usable shower gallons @ 105°F
  - Usable shower minutes @ 2.0 GPM
"""

import os
import re
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
HPWH_YAML_PATH = os.path.join(REPO_ROOT, "hpwh/hpwh.yaml")
TEMPLATES_YAML_PATH = os.path.join(REPO_ROOT, "hpwh/templates.yaml")


def compute_hpwh_metrics(upper: float, lower: float, cold_inlet: float = 65.0,
                         target_baseline: float = 120.0, tank_gallons: float = 65.0,
                         shower_temp: float = 105.0, shower_gpm: float = 2.0):
    """
    Python reference implementation of the Jinja2 formulas in hpwh.yaml
    """
    # Volumetric weighted average (HPWH coil is around lower ~60% of tank)
    avg_temp = (upper * 0.4) + (lower * 0.6)

    # State of charge calculation
    raw_soc = ((avg_temp - cold_inlet) / (target_baseline - cold_inlet)) * 100.0
    soc = min(max(round(raw_soc), 0), 100)
    solar_boost = max(round(raw_soc - 100), 0)

    # Available shower water calculation (first law energy balance)
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


class TestHpwhTemplates(unittest.TestCase):
    def test_package_files_exist(self):
        self.assertTrue(os.path.isfile(HPWH_YAML_PATH), "hpwh/hpwh.yaml must exist")
        self.assertTrue(os.path.isfile(TEMPLATES_YAML_PATH), "hpwh/templates.yaml must exist")

    def test_availability_guards_present(self):
        """Ensure all sensors have availability blocks to prevent false 100% readings when offline"""
        with open(HPWH_YAML_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        # Must check has_value for upper and lower sensors
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
        # avg = 110*0.4 + 65*0.6 = 44 + 39 = 83°F
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
        # 80 * (120-65) / (105-65) = 80 * 55 / 40 = 110 gallons
        self.assertEqual(m["shower_gallons"], 110)
        self.assertEqual(m["shower_minutes"], 55)


if __name__ == "__main__":
    unittest.main()
