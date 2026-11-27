# Y4. Агентные симуляции NoKing v0.5 (`03_simulation`)

## 1. Воспроизведение и окружение

- **Скрипт:** [`sim_noking_v05.py`](sim_noking_v05.py)
- **Инструмент:** Python `3.11.2`, `numpy`, `pandas`, `matplotlib` (`/tmp/noking_venv`).
- **Воспроизводимость:** `20` независимых прогонов (`SEEDS = 100..119`), `95%` ДИ ($1.96 \cdot s / \sqrt{20}$). Сводка: [`summary_v05.json`](summary_v05.json).
- **Статус всех симуляционных выводов:** строго **`SUPPORTED`** (условно от принятых гипотез поведения `herd = 0.60, p_unrev = 0.08, η = 0.05` и логнормального распределения капитала `N = 80`; никогда не `PROVEN-IN-MODEL`).

```bash
cd verification/v0.5/03_simulation
/tmp/noking_venv/bin/python sim_noking_v05.py
```

---

## 2. Сводка экспериментов (`Exp 0–5`)

| Эксперимент | Задача | Что проверялось и диапазон | Выходы (CSV / график) | Ключевые результаты (`95%` ДИ, условно) |
|---|---|---|---|---|
| **Exp 0** | **Y0.1** Расхождение `1.43%` vs `1.83%` и единая база `v0.1..v0.5` | `N ∈ {60, 36}`, `f_mal ∈ [0.10, 0.50]` на идентичном потоке RNG (`seed+300`) | [`data/exp0_y01_discrepancy_audit.csv`](data/exp0_y01_discrepancy_audit.csv)<br>[`data/exp0_unified_v01_v05.csv`](data/exp0_unified_v01_v05.csv)<br>[`plots/fig1_g2_disjoint_and_captured_parent.png`](plots/fig1_g2_disjoint_and_captured_parent.png) | Разница `1.83%` (абляция `seed+200`) и `1.43%` (единая база `seed+300`) вызвана исключительно разными сдвигами RNG. На `N=36, f=40%` регрессия `v0.4` (`9.43% ± 0.75%`) в `v0.5` полностью исчезает (**`0.32% ± 0.11%`**, `0%` fallback) благодаря **G2(a)**. |
| **Exp 1** | **Y4 / G1 + G2(b)** Доля отказов при приёме `e_create` и динамический потолок | `4` гипотезы капитала (`$400..$2000`), `κ_cap ∈ {1.0, 1.25, 1.50}`, поток `250` сделок | [`data/exp1_g1_capacity_rejection.csv`](data/exp1_g1_capacity_rejection.csv)<br>[`plots/fig2_g1_rejection_and_dynamic_vmax.png`](plots/fig2_g1_rejection_and_dynamic_vmax.png) | Цена **G1+G2** при `κ_cap = 1.25`: доля отклонённых сделок равна **`18.08% ± 1.78%`** при Low (`$400`), **`8.48% ± 0.89%`** при Mid (`$600`), **`3.72% ± 0.76%`** при Heavy-tail и **`0.54% ± 0.41%`** при Pro (`$2000`). Динамический потолок Tier 3: `$1 152 / $1 728 / $1 861 / $7 403`. |
| **Exp 2** | **Y4 / G2(a)** Стресс-тест: чистый vs захваченный родитель | `N_local = 36`, `f_mal ∈ [0.10, 0.50]` (`Parent 0.5·f` vs `Parent 1.0·f` vs `GLOBAL 0.25·f`) | [`data/exp2_g2_disjoint_and_captured_parent.csv`](data/exp2_g2_disjoint_and_captured_parent.csv)<br>[`plots/fig1_g2_disjoint_and_captured_parent.png`](plots/fig1_g2_disjoint_and_captured_parent.png) | При `f_mal = 40%`: чистый `Parent` держит **`0.30% ± 0.12%`** (vs `9.90%` локально в v0.4), прямой `GLOBAL` — **`0.00%`**, но при **одновременном захвате `Parent` (`40%`)** ошибки вырастают до **`12.73% ± 1.02%`** (`V5-04`). |
| **Exp 3** | **Y4 / G3** Экономика киперов и потолок `R_keeper_max` | `R_keeper_max ∈ {$2, $3, $4, $5}` vs `v0.4 Uncapped`, `p_rev ∈ [0.10, 0.40]`, `1000` сделок | [`data/exp3_g3_keeper_cap.csv`](data/exp3_g3_keeper_cap.csv)<br>[`plots/fig3_g3_keeper_and_sybil.png`](plots/fig3_g3_keeper_and_sybil.png) | При `p_rev = 30%`: чистый профит честных киперов остаётся положительным (`+$143.69` при `$2` до `+$194.29` при `$5` / 1000 сделок), казна возвращает **`+$62.46..+$11.87` / 1000**, а макс. разовая сивилла-рента сжата до `$1.50–$4.50` (`-$85.50` против `$87` на потолке). |
| **Exp 4** | **Y4** Абляция «минус один» **только для G1, G2, G3** | `N_loc=36, f=40%, Mid Cap`: полный стек `v0.5` минус G1 / G2(a) / G2(b) / G3 | [`data/exp4_loo_g1_g2_g3.csv`](data/exp4_loo_g1_g2_g3.csv)<br>[`plots/fig4_loo_g1_g2_g3.png`](plots/fig4_loo_g1_g2_g3.png) | Полный `v0.5`: `0.17%` ошибок, `0%` пасс. сплита, `0%` R2 нехватки, `$168.80` предел ренты/300 сделок. Без **G1**: `+3.67%` пассивных сплитов; без **G2(a)**: `0.17% → 9.68%` ошибок (`+9.51` п.п.); без **G2(b)**: `+0.67%` R2 нехваток; без **G3**: потолок сивилла-утечки растёт в `3×` (`$168.80 → $507.19`). |
| **Exp 5** | **Доп. F3** Отложенный `reveal` без постревильного добора | `p_unrev ∈ [0.02, 0.16]`, `k=5, Q=3` | [`data/exp5_f3_deferred_reveal.csv`](data/exp5_f3_deferred_reveal.csv) | Если в открытом EVM запретить постревильный добор ради сокрытия счёта (Фаза 2 без добора), провалы кворума растут с `0.00%` (с добором) до **`0.57%`** (`p_unrev=0.08`) и **`3.15%`** (`p_unrev=0.16`), не защищая от reveal-withholding (`V5-05`). |
