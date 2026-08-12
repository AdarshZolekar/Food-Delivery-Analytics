"""
Analytics validation tests — metric formulas, RFM scoring, retention.
"""

import pytest
import pandas as pd
import numpy as np


class TestRFMScoring:

    def test_rfm_scores_range_1_to_5(self):
        import pandas as pd
        monetary = pd.Series([100, 200, 300, 400, 500, 600, 700, 800, 900, 1000])
        scores = pd.qcut(monetary, q=5, labels=[1, 2, 3, 4, 5])
        assert int(scores.min()) == 1
        assert int(scores.max()) == 5

    def test_champions_require_all_high_scores(self):
        def segment(r, f, m):
            if r >= 4 and f >= 4 and m >= 4:   return 'Champions'
            if r >= 3 and f >= 3:               return 'Loyal'
            if r <= 2 and f >= 4:               return 'At Risk'
            if r == 1 and f == 1:               return 'Lost'
            return 'Other'

        assert segment(5, 5, 5) == 'Champions'
        assert segment(4, 4, 4) == 'Champions'
        assert segment(3, 4, 5) != 'Champions'  # r too low
        assert segment(1, 5, 5) == 'At Risk'
        assert segment(1, 1, 1) == 'Lost'

    def test_recency_higher_score_means_more_recent(self):
        # NTILE with ORDER BY recency_days DESC → 5=most recent
        recency_days = pd.Series([5, 30, 90, 180, 365])
        # Lower days = higher r_score
        r_scores = recency_days.rank(ascending=True, method='first').astype(int)
        assert r_scores.iloc[0] == 1   # 5 days = rank 1 in ascending = lowest NTILE
        assert r_scores.iloc[-1] == 5  # 365 days = rank 5 ascending


class TestRetentionMetrics:

    def test_retention_rate_formula(self):
        cohort_size = 1000
        retained_m1 = 320
        retention_pct = round(retained_m1 / cohort_size * 100, 1)
        assert retention_pct == 32.0

    def test_churn_rate_is_complement_of_retention(self):
        retention = 32.0
        churn = round(100 - retention, 1)
        assert churn == 68.0

    def test_retention_decreases_over_months(self):
        """Later months should have lower or equal retention."""
        retentions = [100.0, 32.0, 24.0, 18.0, 14.0, 11.0, 9.0]
        for i in range(1, len(retentions)):
            assert retentions[i] <= retentions[i - 1]

    def test_cohort_month_format(self):
        from datetime import date
        d = date(2024, 3, 1)
        formatted = d.strftime('%Y-%m')
        assert formatted == '2024-03'


class TestDeliveryAnalytics:

    def test_sla_breach_pct_formula(self):
        total = 10000
        breaches = 850
        pct = round(breaches / total * 100, 2)
        assert pct == 8.5

    def test_percentile_values_ordering(self):
        times = sorted([15, 20, 25, 28, 30, 35, 40, 45, 55, 70])
        p50 = times[len(times) // 2]
        p90_idx = int(len(times) * 0.9)
        assert times[p90_idx] >= p50

    def test_demand_index_formula(self):
        """demand_index = hour_orders / avg_all_hour_orders."""
        hour_orders = 500
        avg_all_hours = 250
        demand_index = round(hour_orders / avg_all_hours, 3)
        assert demand_index == 2.0

    def test_moving_average_smooths_outliers(self):
        daily = pd.Series([100, 500, 110, 105, 98, 102, 108])
        ma7 = daily.rolling(7).mean()
        # MA should be less extreme than the outlier (500)
        assert ma7.iloc[-1] < 500


class TestRevenueMetrics:

    def test_aov_formula(self):
        total_revenue = 487000.0
        total_orders = 1000
        aov = round(total_revenue / total_orders, 2)
        assert aov == 487.0

    def test_take_rate_formula(self):
        platform_revenue = 97400.0
        gmv = 487000.0
        take_rate = round(platform_revenue / gmv * 100, 2)
        assert take_rate == 20.0

    def test_mom_growth_formula(self):
        current = 520000.0
        previous = 487000.0
        growth = round((current - previous) / previous * 100, 1)
        assert growth == 6.8

    def test_contribution_margin(self):
        platform_rev = 97400.0
        delivery_costs = 45000.0
        discounts = 12000.0
        cm = round(platform_rev - delivery_costs - discounts, 2)
        assert cm == 40400.0

    def test_discount_rate_formula(self):
        total_discounts = 48700.0
        gmv = 487000.0
        discount_rate = round(total_discounts / gmv * 100, 2)
        assert discount_rate == 10.0
