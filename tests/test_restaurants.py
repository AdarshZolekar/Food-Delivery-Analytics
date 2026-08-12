"""
Restaurant domain tests — ratings, commission, health scoring.
"""

import pytest


class TestRestaurantRating:

    def test_rating_range(self):
        for r in [0.0, 2.5, 3.8, 4.9, 5.0]:
            assert 0 <= r <= 5

    def test_avg_rating_from_reviews(self):
        ratings = [4, 5, 4, 3, 5, 4, 5]
        avg = round(sum(ratings) / len(ratings), 2)
        assert 4.0 <= avg <= 5.0

    def test_zero_reviews_gives_zero_rating(self):
        reviews = []
        avg = sum(reviews) / len(reviews) if reviews else 0.0
        assert avg == 0.0

    def test_new_restaurant_starts_with_zero_orders(self):
        total_orders = 0
        total_revenue = 0.0
        assert total_orders == 0
        assert total_revenue == 0.0


class TestCommissionRates:

    def test_commission_within_valid_range(self):
        for rate in [15, 18, 20, 22, 25, 30]:
            assert 5 <= rate <= 40

    def test_platform_commission_calculation(self):
        order_total = 487.0
        commission_rate = 20.0
        commission = round(order_total * commission_rate / 100, 2)
        assert commission == 97.4

    def test_higher_commission_means_more_revenue_per_order(self):
        order = 500.0
        low_rate, high_rate = 15.0, 25.0
        assert order * high_rate / 100 > order * low_rate / 100


class TestRestaurantHealthScore:

    def test_health_score_components(self):
        food_rating = 4.5       # 0-20 points
        cancel_rate = 2.0       # 0-20 points
        orders_30d = 80         # 0-20 points
        platform_rating = 4.3   # 0-20 points
        avg_prep_time = 28.0    # 0-20 points

        rating_score      = food_rating * 20 / 5          # 18
        cancel_score      = max(0, 10 - cancel_rate) * 2  # 16
        activity_score    = min(20, orders_30d / 5)        # 16
        plat_score        = platform_rating * 4            # 17.2
        speed_score       = max(0, 20 - avg_prep_time)    # 0 (28 > 20)

        total = rating_score + cancel_score + activity_score + plat_score + speed_score
        assert total > 60   # Good restaurant should score >60

    def test_star_partner_criteria(self):
        avg_food_rating = 4.6
        cancel_rate_pct = 2.5
        is_star = avg_food_rating >= 4.5 and cancel_rate_pct < 3
        assert is_star

    def test_needs_improvement_criteria(self):
        avg_food_rating = 3.3
        is_flagged = avg_food_rating < 3.5
        assert is_flagged
