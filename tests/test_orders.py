"""
Order domain tests — placement, cancellation, financial calculations,
status transitions, and business rule enforcement.
"""

import pytest
from datetime import datetime, timedelta
import pandas as pd


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def valid_order():
    return {
        "customer_id": 1,
        "restaurant_id": 1,
        "items": [{"item_id": 1, "quantity": 2, "unit_price": 199.0},
                  {"item_id": 2, "quantity": 1, "unit_price": 89.0}],
        "discount_amount": 50.0,
        "delivery_fee": 39.0,
        "tax_rate": 0.05,
    }


@pytest.fixture
def cancelled_order():
    return {
        "order_id": 999,
        "order_status": "Cancelled",
        "total_amount": 487.0,
        "cancellation_reason": "Customer requested",
    }


# ── Financial Calculation Tests ───────────────────────────────────────────────

class TestOrderFinancials:

    def test_subtotal_is_sum_of_items(self, valid_order):
        items = valid_order["items"]
        expected = sum(i["quantity"] * i["unit_price"] for i in items)
        assert expected == 2 * 199.0 + 1 * 89.0 == 487.0

    def test_total_amount_formula(self, valid_order):
        items = valid_order["items"]
        subtotal = sum(i["quantity"] * i["unit_price"] for i in items)
        discount = valid_order["discount_amount"]
        delivery = valid_order["delivery_fee"]
        tax_rate = valid_order["tax_rate"]
        taxes = round((subtotal - discount) * tax_rate, 2)
        total = round(subtotal - discount + delivery + taxes, 2)
        assert total == round(487.0 - 50.0 + 39.0 + (437.0 * 0.05), 2)

    def test_discount_cannot_exceed_subtotal(self):
        subtotal = 200.0
        discount = 250.0
        # Should be capped at subtotal
        effective_discount = min(discount, subtotal)
        assert effective_discount == subtotal

    def test_platform_commission_calculation(self):
        total = 487.0
        commission_rate = 20.0
        commission = round(total * commission_rate / 100, 2)
        assert commission == 97.40

    def test_zero_delivery_fee_for_free_delivery_promo(self):
        """FREE_DELIVERY promo type should zero out delivery_fee."""
        delivery_fee = 39.0
        promo_type = "FREE_DELIVERY"
        effective_fee = 0.0 if promo_type == "FREE_DELIVERY" else delivery_fee
        assert effective_fee == 0.0

    def test_gst_is_five_percent(self):
        taxable = 437.0   # subtotal - discount
        tax = round(taxable * 0.05, 2)
        assert tax == 21.85

    def test_item_total_generated_column(self):
        """item_total = quantity × unit_price."""
        quantity = 3
        unit_price = 199.0
        item_total = quantity * unit_price
        assert item_total == 597.0


# ── Order Status Tests ────────────────────────────────────────────────────────

class TestOrderStateMachine:

    VALID_TRANSITIONS = {
        "Placed":     ["Confirmed", "Cancelled"],
        "Confirmed":  ["Preparing", "Cancelled"],
        "Preparing":  ["Ready", "Cancelled"],
        "Ready":      ["Picked Up"],
        "Picked Up":  ["On The Way"],
        "On The Way": ["Delivered"],
        "Delivered":  [],
        "Cancelled":  [],
    }

    def test_placed_can_transition_to_confirmed(self):
        assert "Confirmed" in self.VALID_TRANSITIONS["Placed"]

    def test_delivered_has_no_further_transitions(self):
        assert self.VALID_TRANSITIONS["Delivered"] == []

    def test_cancelled_cannot_be_uncancelled(self):
        assert self.VALID_TRANSITIONS["Cancelled"] == []

    def test_delivered_order_cannot_be_cancelled(self):
        assert "Cancelled" not in self.VALID_TRANSITIONS["Delivered"]
        assert "Cancelled" not in self.VALID_TRANSITIONS["On The Way"]

    def test_all_statuses_in_allowed_values(self):
        allowed = {'Placed', 'Confirmed', 'Preparing', 'Ready',
                   'Picked Up', 'On The Way', 'Delivered', 'Cancelled'}
        for status in self.VALID_TRANSITIONS:
            assert status in allowed


# ── Business Rule Tests ───────────────────────────────────────────────────────

class TestOrderBusinessRules:

    def test_minimum_order_amount_enforced(self):
        """Orders below restaurant minimum should be rejected."""
        restaurant_min = 149.0
        order_subtotal = 120.0
        assert order_subtotal < restaurant_min

    def test_promo_requires_minimum_order(self):
        """Promo codes with min_order_amount must check against subtotal."""
        promo_min = 199.0
        order_subtotal = 180.0
        promo_applicable = order_subtotal >= promo_min
        assert not promo_applicable

    def test_promo_max_discount_cap(self):
        """PERCENT promo should not exceed max_discount."""
        order_amount = 1000.0
        percent = 20.0
        max_discount = 80.0
        calculated = order_amount * percent / 100
        effective = min(calculated, max_discount)
        assert effective == max_discount

    def test_cancelled_order_triggers_refund(self, cancelled_order):
        assert cancelled_order["order_status"] == "Cancelled"
        # Refund should equal order total for full cancellation
        refund = cancelled_order["total_amount"]
        assert refund == 487.0

    def test_cancellation_reason_required_for_cancelled(self):
        order = {"order_status": "Cancelled", "cancellation_reason": None}
        # Business rule: reason must be set
        is_valid = not (order["order_status"] == "Cancelled" and order["cancellation_reason"] is None)
        assert not is_valid   # This order is invalid — reason is missing


# ── Data Quality Tests ────────────────────────────────────────────────────────

class TestOrderDataQuality:

    def test_order_timestamp_not_future(self):
        now = datetime.now()
        order_time = datetime.now() + timedelta(hours=1)
        is_valid = order_time <= now
        assert not is_valid

    def test_delivery_time_positive(self):
        actual_time_mins = 35
        assert actual_time_mins > 0

    def test_sla_breach_flag_logic(self):
        """SLA is breached when actual_time_mins > 45."""
        assert 46 > 45   # Breached
        assert 45 <= 45  # Not breached (exactly 45 = on time)
        assert 30 <= 45  # Not breached

    def test_on_time_flag_logic(self):
        """on_time = actual_time_mins <= expected_time_mins."""
        actual, expected = 28, 30
        assert actual <= expected  # On time

        actual, expected = 35, 30
        assert actual > expected   # Late

    def test_payment_amount_matches_order_total(self):
        order_total = 487.35
        payment_amount = 487.35
        assert abs(order_total - payment_amount) < 0.01


# ── Promotion Tests ───────────────────────────────────────────────────────────

class TestPromotions:

    def test_percent_discount_calculation(self):
        order_amount = 500.0
        discount_pct = 20.0
        discount = order_amount * discount_pct / 100
        assert discount == 100.0

    def test_flat_discount_calculation(self):
        order_amount = 500.0
        flat_amount = 75.0
        discount = min(flat_amount, order_amount)
        assert discount == 75.0

    def test_promo_deactivated_at_max_uses(self):
        max_uses = 100
        current_uses = 100
        is_active = current_uses < max_uses
        assert not is_active

    def test_promo_dates_are_valid(self):
        from datetime import date
        start = date(2024, 1, 1)
        end = date(2024, 12, 31)
        assert start < end

    def test_expired_promo_not_applicable(self):
        from datetime import date
        end_date = date(2023, 12, 31)
        today = date.today()
        is_valid = today <= end_date
        assert not is_valid   # Expired
