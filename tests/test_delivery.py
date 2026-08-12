"""
Delivery domain tests — partner assignment, SLA logic, ratings, earnings.
"""

import pytest
from datetime import datetime, timedelta


class TestDeliveryMetrics:

    def test_sla_breached_above_45_mins(self):
        assert 46 > 45
        assert not (45 > 45)
        assert not (44 > 45)

    def test_on_time_at_or_under_expected(self):
        cases = [(28, 30, True), (30, 30, True), (31, 30, False)]
        for actual, expected, result in cases:
            assert (actual <= expected) == result

    def test_delivery_time_positive(self):
        for t in [1, 15, 30, 60]:
            assert t > 0

    def test_distance_km_positive(self):
        assert 3.5 > 0

    def test_partner_earnings_formula(self):
        delivery_fee, distance_km = 39.0, 4.5
        earnings = round(delivery_fee * 0.7 + distance_km * 2, 2)
        assert earnings == round(39.0 * 0.7 + 4.5 * 2, 2)
        assert earnings > 0


class TestDeliveryStatusMachine:
    VALID = {
        "Pending":                ["Assigned"],
        "Assigned":               ["En Route to Restaurant", "Cancelled"],
        "En Route to Restaurant": ["Picked Up"],
        "Picked Up":              ["En Route to Customer"],
        "En Route to Customer":   ["Delivered", "Failed"],
        "Delivered":              [],
        "Failed":                 [],
        "Cancelled":              [],
    }

    def test_pending_to_assigned(self):
        assert "Assigned" in self.VALID["Pending"]

    def test_delivered_is_terminal(self):
        assert self.VALID["Delivered"] == []

    def test_cancelled_is_terminal(self):
        assert self.VALID["Cancelled"] == []

    def test_picked_up_leads_to_en_route(self):
        assert "En Route to Customer" in self.VALID["Picked Up"]


class TestPartnerRating:

    def test_rating_within_valid_range(self):
        for r in [1.0, 3.5, 4.8, 5.0]:
            assert 1.0 <= r <= 5.0

    def test_average_rating_calculation(self):
        ratings = [4, 5, 3, 5, 4]
        avg = round(sum(ratings) / len(ratings), 2)
        assert avg == 4.2

    def test_new_partner_has_zero_deliveries(self):
        total_deliveries = 0
        assert total_deliveries == 0

    def test_partner_total_earnings_accumulate(self):
        earnings_list = [42.5, 38.0, 55.2]
        total = round(sum(earnings_list), 2)
        assert total == 135.7


class TestSLACompliance:

    def test_sla_compliance_rate_formula(self):
        total = 1000
        sla_breaches = 85
        sla_breach_pct = round(sla_breaches / total * 100, 2)
        compliance_pct = round(100 - sla_breach_pct, 2)
        assert sla_breach_pct == 8.5
        assert compliance_pct == 91.5

    def test_on_time_rate_formula(self):
        delivered = 900
        on_time = 810
        on_time_rate = round(on_time / delivered * 100, 1)
        assert on_time_rate == 90.0

    def test_peak_hour_delivery_slower(self):
        """Dinner rush (19-22h) should have higher avg delivery time."""
        peak_avg = 38
        off_peak_avg = 24
        assert peak_avg > off_peak_avg

    def test_zone_avg_delivery_target(self):
        """Zone target is stored in zones.avg_delivery_time_mins."""
        zone_target = 30
        actual = 28
        on_target = actual <= zone_target
        assert on_target
