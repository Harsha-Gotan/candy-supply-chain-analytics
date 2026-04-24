# 🍬 Candy Distributor — Supply Chain & Distribution Analytics

> **An end-to-end supply chain analytics project** combining PostgreSQL, Python and Power BI to analyse 4 years of historical sales, diagnose supply chain health, forecast 2025 demand and assess inventory risk.

---

**👤 Author:** Harsha Gotan
**📅 Year:** 2025
**🎯 Domain:** Supply Chain Analytics | Data Analysis

---

## 📌 Table of Contents

- [Business Problem](#-business-problem)
- [Project Goal](#-project-goal)
- [Dataset Overview](#-dataset-overview)
- [Tech Stack](#-tech-stack)
- [Project Architecture](#-project-architecture)
- [Project Walkthrough](#-project-walkthrough)
- [Key Visuals](#-key-visuals)
- [Business Insights & Impact](#-business-insights--impact)
- [Recommendations](#-recommendations)
- [How to Reproduce](#-how-to-reproduce)
- [Project Structure](#-project-structure)
- [Limitations & Caveats](#-limitations--caveats)

---

## 🧩 Business Problem

A fictional candy distributor — inspired by Willy Wonka's product universe — operates across 4 US regions, sources from 5 manufacturing factories and sells 15 products across Chocolate, Sugar and Other divisions.

The business had 4 years of historical sales data but **no visibility into**:
- Whether suppliers were meeting delivery commitments
- Which products were at risk of running out of stock in 2025
- What demand would look like for the coming year
- Whether current inventory levels could support forecasted demand

This project was built to answer all of those questions through a structured, end-to-end analytical pipeline.

---

## 🎯 Project Goal

Build a complete supply chain analytics solution that moves from raw historical data to forward-looking business intelligence — answering five core questions:

| Section | Business Question |
|---|---|
| **Sales Analysis** | What has the business performed like over 2021–2024? |
| **Supply Chain Diagnostic** | Are our suppliers and factories performing reliably? |
| **Demand Forecasting** | What demand should we expect in 2025? |
| **Inventory Risk** | Can our current inventory support forecasted demand? |
| **Recommendations** | What actions should the business take? |

---

## 📦 Dataset Overview

The project uses **8 data tables** — 5 sourced from a public dataset and 3 independently simulated to complete the supply chain picture.

### Original Tables (sourced)
| Table | Rows | Description |
|---|---|---|
| Candy_Sales.csv | 10,194 | Transaction-level sales data (2021–2024) |
| Candy_Products.csv | 15 | Product master — division, factory, pricing |
| Candy_Factories.csv | 5 | Factory locations (lat/lng) |
| Candy_Targets.csv | 3 | Annual revenue targets by division |
| uszips.csv | 33,786 | US ZIP code enrichment for geographic mapping |

### Simulated Tables (independently created)
| Table | Rows | Description | Reason for Simulation |
|---|---|---|---|
| Inventory_Dataset_Fixed.csv | 180 | Monthly stock levels per product (2025) | Missing from original dataset |
| Supplier_Performance.csv | 5 | Lead times, delay rates, reliability scores | Missing from original dataset |
| Expected_Delivery.csv | 5 | Contracted SLA delivery days per factory | Missing from original dataset |

> **Note on simulation:** The three simulated tables were built using realistic supply chain logic — inventory levels calibrated to actual historical sales volumes, safety stock set at 1.2x monthly demand, reorder points at 2x monthly demand, and seasonal demand multipliers derived from historical patterns. Simulation decisions are documented in the Python notebook.

> **Note on ship dates:** The original dataset contained unrealistic ship dates (2026–2030). These were re-simulated with realistic lead times differentiated by ship mode — Same Day (1–2 days), First Class (3–5 days), Second Class (6–10 days), Standard Class (11–20 days).

---

## 🛠️ Tech Stack

| Tool | Role | Why This Tool |
|---|---|---|
| **PostgreSQL** | Data storage, cleaning, analysis | Industry-standard relational database — handles all data preparation and analytical queries |
| **Python** | Demand forecasting | SQL cannot perform time series forecasting — Python's scikit-learn handles trend + seasonality modelling |
| **Power BI** | Interactive dashboard | Business-facing visualisation — connects live to PostgreSQL for always-fresh data |

Each tool does what it's genuinely best at. This mirrors how real data teams operate.

---

## 🏗️ Project Architecture

```
Raw CSVs
    ↓
PostgreSQL (candy schema)
    ├── File 1: Schema creation & data loading
    ├── File 2: Data cleaning → clean_sales, clean_products,
    │           clean_supplier, clean_inventory, v_sales_enriched
    ├── File 3: Sales Performance Analysis (11 queries)
    ├── File 4: Supply Chain Diagnostic (6 queries)
    └── File 5: Inventory Analysis + forecast coverage (6 queries)
         ↑
         └── forecast_2025.csv (from Python)

Python (forecasting.ipynb)
    ├── Monthly aggregation per product
    ├── Feature engineering (trend + seasonality)
    ├── Train on 2021–2023 → validate on 2024 (MAPE)
    ├── Retrain on full data → forecast Jan–Dec 2025
    └── Export: forecast_2025.csv → SQL
                forecast_2025_full.csv → Power BI
                forecast_validation.csv → Power BI

Power BI (live PostgreSQL connection)
    ├── Page 1: Executive Summary
    ├── Page 2: Sales Deep Dive
    ├── Page 3: Supply Chain Diagnostic
    ├── Page 4: Inventory & Stockout Risk
    └── Page 5: Demand Forecast 2025
```

---

## 🔍 Project Walkthrough

### Section 1 — Sales Performance Analysis (2021–2024)
Using PostgreSQL, 11 analytical queries were written to understand the business baseline — KPIs, year-over-year growth, division performance vs targets, product rankings, regional breakdown and seasonality patterns. Key finding: revenue was flat in 2022 then accelerated +27.4% in both 2023 and 2024.

### Section 2 — Supply Chain Diagnostic
Six queries connecting sales to supplier performance data. Introduced a **composite risk score** (weighted formula combining delay rate, lead time gap and reliability score) to rank factories by operational risk. Built a supplier risk matrix classifying each factory into quadrants (Critical, Stable, Monitor, Efficient) based on revenue contribution and reliability.

### Section 3 — Demand Forecasting (Python)
Built a **Linear Regression model with trend and seasonality features** for each of the 15 products. Validated on a 2024 holdout set using MAPE before forecasting 2025. Products with insufficient data (7 low-selling products) were handled with a simple monthly average approach — documented honestly in the notebook. Average MAPE across high-revenue products: ~19%.

### Section 4 — Inventory Planning & Stockout Risk
Combined the Python forecast output with the 2025 inventory table in PostgreSQL. Calculated a **coverage ratio** (closing stock ÷ forecasted demand) for each product-month combination. Created a four-tier stock status classification: 🔴 Critical, 🟠 Reorder Now, 🟡 Demand Gap, 🟢 Healthy.

### Section 5 — Recommendations
Data-backed recommendations derived from findings across all four sections — documented in the Power BI dashboard and summarised below.

---

## 📊 Key Visuals

### Page 1 — Executive Summary
- **6 KPI cards**: Total Revenue ($141.25K), Gross Profit ($93.08K), Gross Margin % (65.9%), Units Sold (39K), Unique Customers (5K), Revenue CAGR (17.43%)
- **Annual Revenue vs Gross Profit** — clustered column chart showing 2021–2024 trajectory
- **Monthly Seasonality Pattern** — line chart showing clear Q4 demand uplift (Nov-Dec peak)
- **Revenue by Division** — donut chart (Chocolate 92.86%, Other 6.84%, Sugar 0.3%)
- **Revenue by Region** — horizontal bars (Pacific 46K > Atlantic 41K > Interior 32K > Gulf 22K)

### Page 2 — Sales Deep Dive
- **Revenue by Product** — 15 products ranked by 4-year revenue
- **Monthly Revenue Trend** — 4 separate year lines (2021–2024) showing growth acceleration
- **Revenue vs Margin % Scatter** — bubble chart with division color coding and average margin reference line
- **Revenue by Geography** — bubble map showing US revenue density by ZIP code

### Page 3 — Supply Chain Diagnostic
- **Factory Locations & Revenue Contribution** — bubble map with 5 factories sized by revenue
- **Supplier Reliability Score** — ranked horizontal bars with 85% target line
- **Actual Lead Time vs Expected SLA** — clustered bars showing which factories breach their commitments
- **Factory Performance Summary** — table with conditional formatting on SLA Status

### Page 4 — Inventory & Stockout Risk
- **Coverage Ratio Heatmap** — 15 products × 12 months with red/yellow/green color scale — the most analytically sophisticated visual in the project
- **Products Below Reorder Point by Month** — column chart showing Q4 risk concentration
- **Months at Stockout Risk by Product** — horizontal bars with WB - Milk Chocolate highlighted critical
- **Monthly Stock Levels vs Thresholds** — 3-line chart showing stock depletion crossing reorder and safety stock lines in November

### Page 5 — Demand Forecast 2025
- **2025 Monthly Forecast by Units** — column chart showing clear Q4 demand peak (Nov: 1,814 units, Dec: 1,794 units)
- **2025 Forecasted Units by Product** — ranked horizontal bars
- **Forecast Model Accuracy (MAPE table)** — color coded: green < 20%, orange 20–50%, red > 50% — shows intellectual honesty about model limitations

---

## 💡 Business Insights & Impact

### 1. Revenue Growth is Accelerating but Concentrated
Revenue grew +27.4% in both 2023 and 2024 — but 92.9% of that revenue comes from a single division (Chocolate) and just 5 products. The business has essentially no revenue diversification. Any disruption to the Chocolate product line directly threatens the entire business.

### 2. Two Factories Generate 92.8% of Revenue — Both Are Over SLA
Lot's O' Nuts (53.8% of revenue) and Wicked Choccy's (39.0% of revenue) are both running above their contracted delivery SLA. Lot's O' Nuts averages 3.4 days beyond commitment; Wicked Choccy's averages 4.2 days over. The business's entire revenue base depends on suppliers who are consistently late.

### 3. Standard Class Shipping is Systemically Broken
Standard Class shipments — representing 60% of all orders — exceed SLA across every factory. Average actual lead time is 15.5 days against an 8-day SLA. This is not a factory problem — it's a shipping mode problem affecting the entire distribution network.

### 4. All 15 Products are Single-Sourced
Every product in the portfolio is manufactured by exactly one factory. There is zero supplier redundancy. A single factory disruption — fire, strike, supply shortage — would eliminate that product entirely with no backup source.

### 5. Q4 Inventory Risk is Concentrated and Predictable
7 of 15 products face stockout risk in Q4 2025. Wonka Bar Milk Chocolate hits critical status in November with only 48% coverage of forecasted demand — the most severe risk in the dataset. All stockout events occur between August and December. This is fully predictable from the seasonal demand pattern identified in the sales analysis and could be prevented with proactive Q3 inventory positioning.

### 6. The Gulf Region is Significantly Underpenetrated
The Gulf region generates only 15.7% of revenue despite being one of four operating regions. Pacific and Atlantic each generate roughly 2x Gulf's volume. Customer count is the limiting factor — revenue per customer is consistent across all regions, meaning the Gulf has a customer acquisition problem, not a pricing or product problem.

---

## ✅ Recommendations

### R1 — Pre-position Q4 Inventory in Q3
**Finding:** 7 products face stockout risk in Q4 — all preventable with earlier ordering.
**Action:** Place replenishment orders for high-risk products (Wonka Bar Milk Chocolate, Nutty Crunch Surprise, Scrumdiddlyumptious) in July–August. Given factory lead times of 3–11 days, orders placed by mid-August will arrive well before September demand begins accelerating. Do not wait for the reorder point to trigger — use the seasonal forecast to pre-position stock proactively.

### R2 — Hold Lot's O' Nuts and Wicked Choccy's Accountable to SLA
**Finding:** Both factories — generating 92.8% of revenue — are consistently breaching delivery commitments.
**Action:** Initiate formal SLA review meetings with both factories. Introduce contractual penalty clauses for persistent lead time breaches. Monitor monthly — if breach continues for 2+ consecutive months escalate to alternative supplier evaluation. Given single-sourcing risk, even initiating supplier diversification conversations adds leverage.

### R3 — Investigate Standard Class Delivery Performance
**Finding:** Standard Class averages 15.5 days actual vs 8-day SLA across all factories.
**Action:** Audit the Standard Class shipping process — the problem is systemic, not factory-specific. Either the SLA commitment is unrealistic and needs renegotiating, or the logistics process needs restructuring. Consider shifting high-value orders to Second Class or First Class to improve delivery reliability for key customers.

### R4 — Develop a Gulf Region Growth Strategy
**Finding:** Gulf generates 15.7% of revenue — roughly half of comparable regions — due to lower customer count, not lower spend per customer.
**Action:** Launch a targeted customer acquisition campaign in Gulf states. Since revenue per customer is consistent with other regions, new customers added in the Gulf will generate equivalent revenue. A 20% increase in Gulf customer count would add approximately $4,500 in annual revenue — achievable through regional sales representation or distributor partnerships.

### R5 — Conduct a Sugar Division Strategic Review
**Finding:** Sugar division generated only $427 in revenue over 4 years against a $60,000 four-year target — a 99.3% miss.
**Action:** Either invest deliberately in Sugar division development (new products, dedicated sales effort, pricing review) or formally deprioritise it and reallocate resources to Chocolate growth. Operating a division at 0.7% of target without a strategic response is a resource drain. A clear decision either way is better than the current ambiguity.

---

## ⚙️ How to Reproduce

### Prerequisites
- PostgreSQL 14+ installed
- Python 3.9+ with: `pandas`, `numpy`, `matplotlib`, `seaborn`, `scikit-learn`
- Power BI Desktop (free)

### Step 1 — Set up the database
```sql
-- Create database
CREATE DATABASE candy_distributor;

-- Run the SQL file
-- Connect to candy_distributor and execute:
-- candy_supply_chain.sql
```

### Step 2 — Import CSVs
Using pgAdmin's Import/Export tool, import each CSV into its corresponding raw table (see SQL file Section 1 for table names and column mappings).

### Step 3 — Run the master setup
```sql
SET search_path TO candy;
-- Run Section 2 of candy_supply_chain.sql
-- This builds all clean tables and views
```

### Step 4 — Run the Python notebook
```bash
jupyter notebook python/forecasting.ipynb
```
Update the file paths in Cell 2 to match your local `data/` folder. Run all cells in order. Three CSV files will be exported to `data/exports/`.

### Step 5 — Load forecast into PostgreSQL
Import `data/exports/forecast_2025.csv` into the `forecast_2025_staging` table using pgAdmin Import tool.

### Step 6 — Connect Power BI
- Open `powerbi/candy_supply_chain_dashboard.pbix`
- When prompted, enter your PostgreSQL connection details: Server = `localhost`, Database = `candy_distributor`
- All visuals will load automatically from the live database connection

---

## 📁 Project Structure

```
candy-supply-chain-analytics/
│
├── 📁 data/
│   ├── Candy_Sales.csv
│   ├── Candy_Products.csv
│   ├── Candy_Factories.csv
│   ├── Candy_Targets.csv
│   ├── Expected_Delivery.csv
│   ├── Supplier_Performance.csv
│   ├── Inventory_Dataset_Fixed.csv
│   └── exports/
│       ├── forecast_2025.csv
│       ├── forecast_2025_full.csv
│       └── forecast_validation.csv
│
├── 📁 sql/
│   └── candy_supply_chain.sql          ← All SQL in one organised file
│
├── 📁 python/
│   └── forecasting.ipynb               ← Demand forecasting notebook
│
├── 📁 powerbi/
│   ├── candy_supply_chain_dashboard.pbix
│   └── candy_supply_chain_dashboard.pdf ← Dashboard screenshots (no PBI needed)
│
└── README.md
```

---

## ⚠️ Limitations & Caveats

| Limitation | Detail |
|---|---|
| **Simulated tables** | Inventory, Supplier Performance and Expected Delivery were independently simulated. Findings from those sections illustrate the analytical framework rather than ground-truth operational data. |
| **Dataset scale** | Total revenue of $141K over 4 years is not realistic for a distributor — this is an educational dataset. The methodology is directly transferable to real business data. |
| **Forecast model** | Linear Regression with trend + seasonality features was chosen deliberately over complex ML models given only ~48 monthly observations per product. Average MAPE of ~19% on high-revenue products is acceptable for monthly demand forecasting. |
| **Ship date simulation** | Original ship dates were unrealistic (2026–2030). Re-simulated with realistic lead time ranges per ship mode. |
| **Single-sourcing** | All 15 products are single-sourced in the dataset — real distributors typically have backup suppliers. The single-source risk finding is therefore an analytical exercise rather than a field-validated concern. |

---

## 🙏 Acknowledgements

- Dataset inspired by the Willy Wonka fictional universe — sourced from a public educational dataset
- Three tables (Inventory, Supplier Performance, Expected Delivery) independently simulated to complete the supply chain picture
- Built as a portfolio project to demonstrate end-to-end supply chain analytics capabilities


## Screenshots

<img width="1443" height="813" alt="page1_executive_summary" src="https://github.com/user-attachments/assets/99a691e0-1053-4710-bf17-bfccb9b4015e" />
![Executive Summary](screenshots/page1_executive_summary.png)

