"""Shared pytest fixtures."""
import pytest


@pytest.fixture
def sample_order_items():
    return [
        {"item_id": 1, "quantity": 2, "unit_price": 199.0},
        {"item_id": 2, "quantity": 1, "unit_price": 89.0},
    ]


@pytest.fixture
def sample_promo():
    return {
        "promo_code": "SAVE20",
        "promo_type": "PERCENT",
        "discount_value": 20.0,
        "min_order_amount": 199.0,
        "max_discount": 80.0,
    }
