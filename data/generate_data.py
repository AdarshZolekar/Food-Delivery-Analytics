"""
Food delivery platform synthetic data generator.
Produces 100K customers, 5K restaurants, 10K delivery partners, 1M orders
with realistic temporal patterns (lunch rush, dinner peak, weekends, festivals).

Usage:
    python data/generate_data.py
    python data/generate_data.py --customers 10000 --orders 100000
"""

import argparse
import csv
import json
import os
import random
from datetime import date, datetime, timedelta
from pathlib import Path
import numpy as np
import pandas as pd
from faker import Faker
from tqdm import tqdm

fake = Faker('en_IN')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

# ── Reference Data ────────────────────────────────────────────────────────────

CITIES = [
    (1, 'Mumbai',    'Maharashtra', 'Asia/Kolkata'),
    (2, 'Delhi',     'Delhi',       'Asia/Kolkata'),
    (3, 'Bangalore', 'Karnataka',   'Asia/Kolkata'),
    (4, 'Hyderabad', 'Telangana',   'Asia/Kolkata'),
    (5, 'Chennai',   'Tamil Nadu',  'Asia/Kolkata'),
    (6, 'Pune',      'Maharashtra', 'Asia/Kolkata'),
    (7, 'Kolkata',   'West Bengal', 'Asia/Kolkata'),
    (8, 'Ahmedabad', 'Gujarat',     'Asia/Kolkata'),
    (9, 'Jaipur',    'Rajasthan',   'Asia/Kolkata'),
    (10,'Lucknow',   'Uttar Pradesh','Asia/Kolkata'),
]

CUISINES = [
    'North Indian', 'South Indian', 'Chinese', 'Italian', 'Mexican',
    'Fast Food', 'Pizza', 'Biryani', 'Rolls & Wraps', 'Desserts',
    'Beverages', 'Healthy', 'Seafood', 'Mughlai', 'Continental',
    'Street Food', 'Thai', 'Japanese', 'Middle Eastern', 'Bakery',
]

VEHICLE_TYPES = ['Motorbike', 'Bicycle', 'Scooter', 'Car']
VEHICLE_WEIGHTS = [0.55, 0.15, 0.25, 0.05]

PAYMENT_METHODS = ['UPI', 'Credit Card', 'Debit Card', 'Cash', 'Wallet', 'NetBanking']
PAYMENT_WEIGHTS = [0.45, 0.20, 0.15, 0.10, 0.08, 0.02]

ORDER_CHANNELS = ['App', 'Web', 'Phone']
CHANNEL_WEIGHTS = [0.72, 0.23, 0.05]

ORDER_STATUSES = ['Delivered', 'Delivered', 'Delivered', 'Delivered',
                   'Delivered', 'Delivered', 'Delivered',
                   'Cancelled', 'Cancelled']

ISSUE_TYPES = ['Wrong Item', 'Missing Item', 'Late Delivery',
                'Cancelled by Restaurant', 'Payment Issue',
                'Refund Request', 'Quality Issue', 'Other']

CANCELLATION_REASONS = [
    'Changed mind', 'Ordered by mistake', 'Restaurant too busy',
    'Estimated time too long', 'Found better option', 'Payment failed',
    'No delivery partner available', 'Restaurant closed'
]

ACQUISITION_CHANNELS = ['Organic', 'Referral', 'Google Ads', 'Meta Ads',
                          'Influencer', 'App Store', 'Word of Mouth']

FOOD_ITEM_TEMPLATES = [
    ('Butter Chicken', 'North Indian', True,  350, 280),
    ('Paneer Tikka',   'North Indian', True,  290, 210),
    ('Masala Dosa',    'South Indian', True,  120,  90),
    ('Margherita Pizza','Pizza',        True,  250, 320),
    ('Chicken Biryani','Biryani',      False, 320, 350),
    ('Veg Fried Rice', 'Chinese',      True,  180, 200),
    ('Chicken Burger', 'Fast Food',    False, 180, 420),
    ('Hakka Noodles',  'Chinese',      True,  160, 280),
    ('Dal Makhani',    'North Indian', True,  220, 310),
    ('Chocolate Cake', 'Desserts',     True,  150, 380),
    ('Cold Coffee',    'Beverages',    True,   90, 120),
    ('Veg Pizza',      'Pizza',        True,  220, 280),
    ('Samosa',         'Street Food',  True,   40,  80),
    ('Gulab Jamun',    'Desserts',     True,   60, 200),
    ('Fish Curry',     'Seafood',      False, 280, 240),
    ('Pad Thai',       'Thai',         False, 280, 320),
    ('Sushi Platter',  'Japanese',     False, 480, 290),
    ('Kebab Rolls',    'Rolls & Wraps',False, 160, 310),
    ('Smoothie Bowl',  'Healthy',      True,  180, 220),
    ('Chicken Tikka',  'Mughlai',      False, 310, 260),
]

# ── Temporal patterns ─────────────────────────────────────────────────────────

def get_order_datetime(rng: np.random.Generator, start_date: date, end_date: date) -> datetime:
    """Generate a realistic order timestamp with lunch/dinner/weekend peaks."""
    total_days = (end_date - start_date).days
    day_offset = rng.integers(0, total_days)
    order_date = start_date + timedelta(days=int(day_offset))

    # Hour distribution: peaks at 12-14 (lunch) and 19-22 (dinner)
    hour_weights = [
        0.3, 0.2, 0.1, 0.1, 0.1, 0.2,   # 00-05
        0.5, 1.0, 1.5, 1.2, 1.0, 1.5,   # 06-11
        3.5, 3.8, 2.5, 1.5, 1.2, 1.5,   # 12-17 (lunch peak)
        2.0, 4.5, 5.0, 4.0, 2.5, 1.2,   # 18-23 (dinner peak)
    ]
    # Boost weekends ~30%
    if order_date.weekday() >= 5:
        hour_weights = [w * 1.3 for w in hour_weights]

    total_w = sum(hour_weights)
    hour_probs = [w / total_w for w in hour_weights]
    hour = int(rng.choice(24, p=hour_probs))
    minute = int(rng.integers(0, 60))
    second = int(rng.integers(0, 60))

    return datetime(order_date.year, order_date.month, order_date.day,
                    hour, minute, second)


def delivery_time_for_hour(hour: int, rng: np.random.Generator) -> int:
    """Delivery time varies with congestion. Peak hours are slower."""
    if 12 <= hour <= 14 or 19 <= hour <= 22:
        base = rng.integers(25, 55)     # Peak: 25-55 mins
    elif 7 <= hour <= 9:
        base = rng.integers(20, 40)     # Morning: 20-40 mins
    else:
        base = rng.integers(15, 35)     # Off-peak: 15-35 mins
    return int(base)


# ── Generators ────────────────────────────────────────────────────────────────

class FoodDeliveryGenerator:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.rng = np.random.default_rng(cfg['seed'])
        self.start_date = date.today() - timedelta(days=365 * cfg['history_years'])
        self.end_date   = date.today()
        self.out = Path(cfg['output_dir'])
        self.out.mkdir(exist_ok=True)

    def generate_seed_data(self) -> None:
        """Write seed_data.sql with cities, zones, and reference records."""
        print("  Generating seed SQL...")
        sql_path = self.out / 'seed_data.sql'
        lines = ["-- Auto-generated seed data\nBEGIN;\n"]

        # Cities
        for cid, name, state, tz in CITIES:
            lines.append(
                f"INSERT INTO cities(city_id,city_name,state,country,timezone) VALUES "
                f"({cid},'{name}','{state}','India','{tz}') ON CONFLICT DO NOTHING;"
            )

        # Zones (10 per city)
        zone_id = 1
        lines.append("")
        for cid, city, _, _ in CITIES:
            for z in range(1, 11):
                lat = round(float(self.rng.uniform(12.0, 28.0)), 6)
                lng = round(float(self.rng.uniform(72.0, 88.0)), 6)
                avg_t = int(self.rng.integers(20, 40))
                lines.append(
                    f"INSERT INTO zones(zone_id,city_id,zone_name,latitude,longitude,avg_delivery_time_mins) "
                    f"VALUES ({zone_id},{cid},'{city} Zone {z}',{lat},{lng},{avg_t}) ON CONFLICT DO NOTHING;"
                )
                zone_id += 1

        # Reset sequences
        lines.append(f"\nSELECT setval('cities_city_id_seq', {len(CITIES)});")
        lines.append(f"SELECT setval('zones_zone_id_seq', {zone_id - 1});")
        lines.append("\nCOMMIT;")

        sql_path.write_text('\n'.join(lines))
        print(f"    ✓ seed_data.sql written")

    def generate_restaurants(self) -> pd.DataFrame:
        n = self.cfg['n_restaurants']
        print(f"  Generating {n:,} restaurants...")
        rows = []
        for i in range(n):
            city = CITIES[int(self.rng.integers(0, len(CITIES)))]
            cid = city[0]
            zone_id = int((cid - 1) * 10 + self.rng.integers(1, 11))
            cuisine = CUISINES[int(self.rng.integers(0, len(CUISINES)))]
            rows.append({
                'restaurant_name':        fake.company() + f" {cuisine}",
                'cuisine_type':           cuisine,
                'city_id':                cid,
                'zone_id':                zone_id,
                'owner_name':             fake.name(),
                'phone':                  fake.phone_number()[:15],
                'email':                  fake.email(),
                'address':                fake.address().replace('\n', ', '),
                'rating':                 round(float(self.rng.uniform(2.5, 5.0)), 2),
                'avg_delivery_time_mins': int(self.rng.integers(20, 50)),
                'min_order_amount':       float(self.rng.choice([0, 99, 149, 199, 249])),
                'commission_rate':        float(self.rng.choice([15, 18, 20, 22, 25, 30])),
                'is_active':              bool(self.rng.random() > 0.05),
                'is_pure_veg':            bool(self.rng.random() < 0.25),
                'joining_date':           str(self.start_date + timedelta(
                                              days=int(self.rng.integers(0, 365)))),
            })
        df = pd.DataFrame(rows)
        df.index = df.index + 1
        df.index.name = 'restaurant_id'
        df.to_csv(self.out / 'restaurants.csv', index=True)
        print(f"    ✓ {n:,} restaurants → restaurants.csv")
        return df

    def generate_menu_items(self, restaurants: pd.DataFrame) -> pd.DataFrame:
        print(f"  Generating menu items...")
        rows = []
        cat_id = 1
        item_id = 1
        for rid in restaurants.index:
            cuisine = restaurants.loc[rid, 'cuisine_type']
            # 3-6 categories per restaurant
            n_cats = int(self.rng.integers(3, 7))
            for cat_n in range(n_cats):
                cat_rows = [r for r in FOOD_ITEM_TEMPLATES
                            if r[1] == cuisine or self.rng.random() < 0.3]
                if not cat_rows:
                    cat_rows = FOOD_ITEM_TEMPLATES
                for item_row in self.rng.choice(len(cat_rows),
                                                 size=min(int(self.rng.integers(3, 8)), len(cat_rows)),
                                                 replace=False):
                    tmpl = cat_rows[item_row]
                    price_adj = float(self.rng.uniform(0.85, 1.25))
                    rows.append({
                        'item_id':       item_id,
                        'restaurant_id': rid,
                        'category_id':   cat_id,
                        'item_name':     tmpl[0],
                        'price':         round(tmpl[4] * price_adj / 10) * 10,
                        'is_available':  bool(self.rng.random() > 0.05),
                        'is_vegetarian': tmpl[2],
                        'calories':      int(tmpl[3] * float(self.rng.uniform(0.9, 1.1))),
                        'is_bestseller': bool(self.rng.random() < 0.15),
                    })
                    item_id += 1
                cat_id += 1

        df = pd.DataFrame(rows)
        df.to_csv(self.out / 'menu_items.csv', index=False)
        print(f"    ✓ {len(df):,} menu items → menu_items.csv")
        return df

    def generate_customers(self) -> pd.DataFrame:
        n = self.cfg['n_customers']
        print(f"  Generating {n:,} customers...")
        rows = []
        for i in range(n):
            city = CITIES[int(self.rng.integers(0, len(CITIES)))]
            reg_days = int(self.rng.integers(0, (self.end_date - self.start_date).days))
            rows.append({
                'customer_id':       i + 1,
                'customer_name':     fake.name(),
                'email':             f"user{i+1}@swifteats.in",
                'phone':             f"+91{int(self.rng.integers(7000000000, 9999999999))}",
                'city_id':           city[0],
                'registration_date': str(self.start_date + timedelta(days=reg_days)),
                'is_active':         bool(self.rng.random() > 0.04),
                'customer_tier':     'Bronze',
                'acquisition_channel': self.rng.choice(ACQUISITION_CHANNELS),
            })
        df = pd.DataFrame(rows)
        df.to_csv(self.out / 'customers.csv', index=False)
        print(f"    ✓ {n:,} customers → customers.csv")
        return df

    def generate_delivery_partners(self) -> pd.DataFrame:
        n = self.cfg['n_delivery_partners']
        print(f"  Generating {n:,} delivery partners...")
        rows = []
        for i in range(n):
            city = CITIES[int(self.rng.integers(0, len(CITIES)))]
            cid = city[0]
            rows.append({
                'partner_id':       i + 1,
                'partner_name':     fake.name(),
                'phone':            f"+91{int(self.rng.integers(7000000000, 9999999999))}",
                'email':            fake.email(),
                'city_id':          cid,
                'zone_id':          int((cid - 1) * 10 + self.rng.integers(1, 11)),
                'vehicle_type':     self.rng.choice(VEHICLE_TYPES, p=VEHICLE_WEIGHTS),
                'is_active':        bool(self.rng.random() > 0.08),
                'current_status':   'Offline',
                'rating':           round(float(self.rng.uniform(3.0, 5.0)), 2),
                'joining_date':     str(self.start_date + timedelta(
                                        days=int(self.rng.integers(0, 365)))),
                'bg_verification':  bool(self.rng.random() > 0.1),
            })
        df = pd.DataFrame(rows)
        df.to_csv(self.out / 'delivery_partners.csv', index=False)
        print(f"    ✓ {n:,} delivery partners → delivery_partners.csv")
        return df

    def generate_orders(self, customers: pd.DataFrame,
                         restaurants: pd.DataFrame,
                         menu_items: pd.DataFrame,
                         partners: pd.DataFrame) -> None:
        n = self.cfg['n_orders']
        print(f"  Generating {n:,} orders (writing monthly CSV files)...")

        # Power-law customer distribution
        n_cust = len(customers)
        cust_probs = self.rng.exponential(1.0, n_cust)
        cust_probs /= cust_probs.sum()

        rest_ids = restaurants.index.tolist()
        partner_ids = partners['partner_id'].tolist()
        city_zone_map = {row['city_id']: (row['city_id'] - 1) * 10 + 1
                         for _, row in customers.iterrows()}

        batch_size = 50_000
        file_handles = {}

        for batch_start in tqdm(range(0, n, batch_size), desc="Order batches"):
            batch_n = min(batch_size, n - batch_start)
            order_records = []
            item_records = []
            delivery_records = []
            payment_records = []

            for j in range(batch_n):
                oid = batch_start + j + 1
                cust_idx = int(self.rng.choice(n_cust, p=cust_probs))
                cust_id = int(customers.iloc[cust_idx]['customer_id'])
                rest_id = int(self.rng.choice(rest_ids))
                rest = restaurants.loc[rest_id]
                city_id = int(rest['city_id'])
                zone_id = int((city_id - 1) * 10 + self.rng.integers(1, 11))

                ts = get_order_datetime(self.rng, self.start_date, self.end_date)
                status = self.rng.choice(ORDER_STATUSES)
                channel = self.rng.choice(ORDER_CHANNELS, p=CHANNEL_WEIGHTS)
                payment = self.rng.choice(PAYMENT_METHODS, p=PAYMENT_WEIGHTS)

                # Pick 1-4 items
                rest_items = menu_items[menu_items['restaurant_id'] == rest_id]
                if rest_items.empty:
                    rest_items = menu_items.sample(3, random_state=int(self.rng.integers(0, 1000)))
                n_items = min(int(self.rng.integers(1, 5)), len(rest_items))
                chosen = rest_items.sample(n_items, random_state=int(self.rng.integers(0, 1000)))

                subtotal = sum(
                    int(self.rng.integers(1, 3)) * float(row['price'])
                    for _, row in chosen.iterrows()
                )
                discount = subtotal * float(self.rng.choice([0, 0, 0, 0.1, 0.2, 0.3],
                                                              p=[0.6, 0.1, 0.1, 0.1, 0.05, 0.05]))
                delivery_fee = float(self.rng.choice([0, 29, 39, 49], p=[0.3, 0.3, 0.2, 0.2]))
                taxes = round((subtotal - discount) * 0.05, 2)
                total = round(subtotal - discount + delivery_fee + taxes, 2)
                commission = round(total * float(rest['commission_rate']) / 100, 2)

                cancel_reason = None
                if status == 'Cancelled':
                    cancel_reason = self.rng.choice(CANCELLATION_REASONS)

                order_records.append({
                    'order_id': oid,
                    'customer_id': cust_id,
                    'restaurant_id': rest_id,
                    'zone_id': zone_id,
                    'order_timestamp': ts.strftime('%Y-%m-%d %H:%M:%S'),
                    'order_status': status,
                    'order_channel': channel,
                    'subtotal_amount': round(subtotal, 2),
                    'discount_amount': round(discount, 2),
                    'delivery_fee': delivery_fee,
                    'taxes': taxes,
                    'total_amount': total,
                    'platform_commission': commission,
                    'payment_method': payment,
                    'cancellation_reason': cancel_reason or '',
                })

                for _, item in chosen.iterrows():
                    qty = int(self.rng.integers(1, 3))
                    item_records.append({
                        'order_id': oid,
                        'item_id': int(item['item_id']),
                        'quantity': qty,
                        'unit_price': float(item['price']),
                    })

                # Delivery record for non-cancelled orders
                if status != 'Cancelled' and self.rng.random() > 0.05:
                    partner_id = int(self.rng.choice(partner_ids))
                    act_time = delivery_time_for_hour(ts.hour, self.rng)
                    exp_time = int(zone_id % 10 * 2 + 25)
                    delivered_at = ts + timedelta(minutes=act_time)
                    dist = round(float(self.rng.uniform(0.5, 8.0)), 2)
                    earning = round(delivery_fee * 0.7 + dist * 2, 2)

                    delivery_records.append({
                        'order_id': oid,
                        'partner_id': partner_id,
                        'assigned_at': (ts + timedelta(minutes=2)).strftime('%Y-%m-%d %H:%M:%S'),
                        'delivered_at': delivered_at.strftime('%Y-%m-%d %H:%M:%S'),
                        'actual_time_mins': act_time,
                        'expected_time_mins': exp_time,
                        'distance_km': dist,
                        'delivery_fee': delivery_fee,
                        'delivery_status': 'Delivered' if status == 'Delivered' else 'Failed',
                        'partner_earnings': earning,
                    })

                # Payment
                payment_records.append({
                    'order_id': oid,
                    'amount': total,
                    'payment_method': payment,
                    'payment_status': 'Completed' if status == 'Delivered' else
                                      ('Refunded' if status == 'Cancelled' else 'Completed'),
                    'transaction_id': f"TXN{oid:010d}",
                    'payment_timestamp': ts.strftime('%Y-%m-%d %H:%M:%S'),
                })

            # Write to monthly files
            for rec in order_records:
                month_key = rec['order_timestamp'][:7]
                fpath = self.out / f"orders_{month_key.replace('-','_')}.csv"
                mode = 'a' if fpath.exists() else 'w'
                with open(fpath, mode, newline='') as f:
                    w = csv.DictWriter(f, fieldnames=order_records[0].keys())
                    if mode == 'w':
                        w.writeheader()
                    w.writerow(rec)

            # Append items/deliveries/payments to single files
            for data, fname in [
                (item_records, 'order_items.csv'),
                (delivery_records, 'deliveries.csv'),
                (payment_records, 'payments.csv'),
            ]:
                if not data:
                    continue
                fpath = self.out / fname
                mode = 'a' if fpath.exists() else 'w'
                with open(fpath, mode, newline='') as f:
                    w = csv.DictWriter(f, fieldnames=data[0].keys())
                    if mode == 'w':
                        w.writeheader()
                    w.writerows(data)

        print(f"    ✓ {n:,} orders + items + deliveries + payments written")

    def run(self):
        print("\n" + "=" * 55)
        print(" SwiftEats Data Generator")
        print(f" Seed: {self.cfg['seed']} | Output: {self.out}")
        print("=" * 55)

        self.generate_seed_data()
        restaurants = self.generate_restaurants()
        menu_items = self.generate_menu_items(restaurants)
        customers = self.generate_customers()
        partners = self.generate_delivery_partners()
        self.generate_orders(customers, restaurants, menu_items, partners)

        print("\n" + "=" * 55)
        print(" Generation complete!")
        print(f"  Restaurants:       {len(restaurants):>8,}")
        print(f"  Customers:         {self.cfg['n_customers']:>8,}")
        print(f"  Delivery Partners: {self.cfg['n_delivery_partners']:>8,}")
        print(f"  Orders:            {self.cfg['n_orders']:>8,}")
        print("=" * 55 + "\n")


def main():
    parser = argparse.ArgumentParser(description="SwiftEats data generator")
    parser.add_argument('--customers',  type=int, default=100_000)
    parser.add_argument('--restaurants',type=int, default=5_000)
    parser.add_argument('--partners',   type=int, default=10_000)
    parser.add_argument('--orders',     type=int, default=1_000_000)
    parser.add_argument('--seed',       type=int, default=42)
    parser.add_argument('--output',     type=str, default='data/generated')
    parser.add_argument('--years',      type=int, default=3)
    args = parser.parse_args()

    cfg = {
        'n_customers':         args.customers,
        'n_restaurants':       args.restaurants,
        'n_delivery_partners': args.partners,
        'n_orders':            args.orders,
        'seed':                args.seed,
        'output_dir':          args.output,
        'history_years':       args.years,
    }
    FoodDeliveryGenerator(cfg).run()


if __name__ == '__main__':
    main()
