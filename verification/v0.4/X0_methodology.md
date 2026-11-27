# X0. Методологические исправления и аудит проверяемости (`v0.4`)

Документ закрывает требования **X0.1–X0.6**, без которых выводы верификации `v0.4` не принимаются.

---

## X0.1 Чувствительность к допущениям о поведении (`exp1_behavioral_sensitivity.csv`)

Прежние расчёты (`v0.1`–`v0.3`) фиксировали некалиброванные гипотезы о поведении людей (`herd = 0.60`, `p_unrev = 0.08`, `η = 0.05`, логнормальный капитал `$600`). В [`sim_noking_v04.py`](03_simulation/sim_noking_v04.py) (`Exp 1`, `N = 60`, `f_mal = 0.30`, `20` сидов `100..119`, `250` споров/сид; график [`fig1_behavioral_sensitivity.png`](03_simulation/plots/fig1_behavioral_sensitivity.png)) проведён перебор каждого параметра. **Все численные результаты ниже помечаются как УСЛОВНЫЕ:**

| Варьируемый параметр | Диапазон | `Bare v0.1` | `+Appeal` вклад (`Δ` п.п.) | `+Commit–Reveal` вклад (`Δ` п.п.) | `Full Stack` ошибки (`95%` ДИ) | Условие сохранения вывода |
|---|---|---|---|---|---|---|
| **`herd`** (`p_unrev=0.08, η=0.05`) | `0.0` | `29.06%` | `+24.72` п.п. (`4.34%`) | **`-1.08` п.п. (`30.14%`)** | `1.82% ± 0.27%` | **CR ничего не даёт при `herd = 0`!** Тезис «CR даёт ~10 п.п.» верен **условно при `herd ≥ 0.4–0.6`** |
| **`herd`** | `0.4` → `0.8` | `37.40%` → `45.06%` | `+25.28` → `+24.36` п.п. | `+7.26` → `+14.92` п.п. | `1.82% ± 0.27%` | Вклад **Appeal (~23–25 п.п.) устойчив при любом `herd ∈ [0, 0.8]`** |
| **`p_unrev`** (`herd=0.60, η=0.05`) | `0.0` → `0.16` | `34.94%` → `48.00%` | `+21.98` → `+23.22` п.п. | `+14.32` → `+9.08` п.п. | `1.20%` → `2.90%` (`±0.35%`) | Full Stack держит `< 3%` **условно при `p_unrev ≤ 0.16`** |
| **`η`** (`herd=0.60, p_unrev=0.08`) | `0.02` → `0.10` | `37.94%` → `45.22%` | `+23.72` → `+23.68` п.п. | `+11.46` → `+9.00` п.п. | `0.90%` → `4.24%` (`±0.49%`) | Порог `< 5%` ошибок держится **условно при `η ≤ 0.10`** |
| **`η`** *(критический порог)* | **`0.20`** | `54.16%` | `+22.08` п.п. (`32.08%`) | `+6.22` п.п. (`47.94%`) | **`13.42% ± 1.02%`** | При `η = 0.20` (высокий шум доказательств) предел `< 5%` **нарушается** |

*Дополнительно (`Exp 4`, [`exp4_oversample_liquidity.csv`](03_simulation/data/exp4_oversample_liquidity.csv)):* вывод о достаточности ликвидности арбитров верен **только условно от распределения капитала** — при `Pro ($2000 медиана)` и `OVERSAMPLE = 2×` нехватка R2 равна `0%` до `$5k` (`15%` при `$8 750`), а при `Low ($400)`, `Mid ($600)` и `Heavy-tail ($800, σ=1.4)` нехватка R2 на сделках Tier 2–3 (`$5k–$8 750`) равна **`100%`**.

---

## X0.2 Абляция «полный набор минус один» и парные взаимодействия (`exp2_leave_one_out_ablation.csv`)

Оценка маржинального вклада каждого механизма **поверх всех остальных** (`N = 60`, `300` споров/seed, `20` сидов; условно при `herd = 0.60, p_unrev = 0.08, η = 0.05`, [`fig2_ablation_and_coalitions.png`](03_simulation/plots/fig2_ablation_and_coalitions.png)):

| Конфигурация | `f_mal = 0.20` | **`f_mal = 0.30` (Δ от Full Stack)** | `f_mal = 0.40` | `fallback` (`0.30`) | Вклад механизма поверх остальных |
|---|---|---|---|---|---|
| **`Full Stack` (`F1+F2+CR+Q+Redraw+App`)** | `0.12% ± 0.10%` | **`1.83% ± 0.26%`** (база) | `13.08% ± 1.04%` | `0.0%` | — |
| **`LOO: -Appeal` (только R1)** | `10.15% ± 0.55%` | **`22.92% ± 0.98%`** (**`+21.08` п.п.**) | `41.23% ± 1.07%` | `0.0%` | Апелляция `k'=17` — главный фильтр ошибок |
| **`LOO: -Commit–Reveal` (открытое голосов.)** | `4.18% ± 0.39%` | **`14.78% ± 0.86%`** (**`+12.95` п.п.**) | `34.62% ± 1.03%` | `0.0%` | Условно при `herd=0.6`: CR предотвращает стадный каскад |
| **`LOO: -Quorum` (возврат бага Def. 5.2)** | `0.48% ± 0.17%` | **`4.25% ± 0.54%`** (**`+2.42` п.п.**) | `18.90% ± 1.08%` | `0.0%` | Исключает 0-голосовые ложные победы `FOR_B` |
| **`LOO: -Redraw` (без добора)** | `0.08% ± 0.08%` | **`2.22% ± 0.33%`** (`+0.38` п.п.) | `13.33% ± 0.74%` | **`0.33%`** | Снимает недокворумы; с `F1` утекает меньше сплитов |
| **`LOO: -Escalation F1` (прямой фоллбек)** | `0.10% ± 0.08%` | `1.83% ± 0.28%` (`+0.00` п.п.) | `13.50% ± 0.97%` | **`0.45%`** | При `N=60` снижает fallback (`0.45% → 0%`), критична при малых пулах / в F1 против сплитов |
| `Pair: Appeal + Commit–Reveal` | `0.48%` | `4.25% ± 0.54%` | `18.90%` | `0.0%` | Синергия двух главных фильтров (остаётся баг Def. 5.2) |
| `Pair: Appeal + Quorum+Redraw` (Open) | `4.20%` | `15.07% ± 0.78%` | `34.47%` | `0.30%` | Эффект без CR |
| `Pair: CR + Quorum+Redraw` (без R2) | `10.10%` | `22.95% ± 0.97%` | `41.35%` | `0.42%` | Потолок 1-раундового арбитража |
| `Base: Bare v0.1` | `25.83%` | `40.80% ± 2.04%` | `57.38%` | `0.0%` | Исходная база без защит |

*Сравнение версий на единой базе (`exp2_unified_v01_v04.csv` + эффект F2 `OVERSAMPLE=2×` на малом пуле `N=36`):*  
При `N = 60, f_mal = 30%`: `v0.1 = 17.07%`, `v0.2 = 1.47% (+0.68% D3)`, `v0.3 = 1.43%`, `v0.4 = 1.43%` (0% fallback). При `N = 36, f_mal = 40%`: `v0.3` (`OVERSAMPLE=3×`) не допускает локальный пул к R2 (`36 < 51`) и уходит в более чистый родительский пул (`0.32%` ошибок), тогда как в `v0.4` (`OVERSAMPLE=2×`) порог `34 ≤ 36` позволяет локальному пулу самому судить апелляцию (**`9.43% ± 0.75%`** ошибок, а при `f_mal=50%` — **`40.98%`** vs `1.97%` в v0.3)!

---

## X0.3 Модель коалиций злонамеренных арбитров (`exp3_coalitions.csv`)

Сравнение независимых нарушителей, координированного блока (0 внутренней неявки, единое голосование `FOR_B`) и `p + ε` Dark DAO на сетке `f_mal ∈ [0.10, 0.50]` (`N = 60`):
- **Независимые vs координированный блок:** при `f_mal ≤ 0.25` оба режима держат `< 0.5%` ошибок; при **`f_mal = 0.30`** координированный блок даёт **`1.86% ± 0.40%`** (vs `1.34%` у независимых); порог `5%` пересекается около **`f_mal = 0.35`** (`5.68% ± 0.82%`), затем резкий развал: **`12.62%`** при `f_mal = 0.40` и **`39.12%`** при `f_mal = 0.50`.  
  **Граница применимости (условно при `η = 0.05`):** протокол сохраняет `< 2%` ошибок при доле коалиции **`f_mal ≤ 30%`** и разрушается выше `35%`.
- **Модель `p + ε` Dark DAO:** при наличии финансируемого эскроу-контракта взятки доля ошибок составляет **`100.0%` во всём диапазоне `f_mal ∈ [0.10, 0.50]`**, т.к. переключение становится доминирующей стратегией и для честных арбитров.

---

## X0.4 Аудит нетривиальности инвариантов (Vacuity Audit `v0.1–v0.4`)

### 1. Явный отзыв / понижение прежних статусов (обязательное требование X0.4в)
1. **ОТЗЫВ в `v0.1` (`verification/01_fsm/README.md` & `REPORT.md`):** статус `PROVEN-IN-MODEL` для *«Согласованность (отсутствие гонок дедлайнов)»* по [`fixed_all.log`](../01_fsm/logs/fixed_all.log) **ОТЗЫВАЕТСЯ и понижается до `UNVERIFIED` (текстовый просмотр)**. Причина: проверка лога [`fixed_all.cfg`](../01_fsm/fixed_all.cfg) показала, что в нём вообще **не было** инварианта `Inv_NoDeadlineRace` или `Inv_NoSimultaneousEnablement`.
2. **ОТЗЫВ / УТОЧНЕНИЕ в `v0.2` (`verification/v0.2/REPORT_v0.2.md` & `V1_traceability.md` строка `A-09 / TLC-5`):**
   - В основном модуле [`NoKingV02.tla`](../v0.2/01_fsm/NoKingV02.tla) (`v02_d9a`, `v02_d9b`, `v02_panel5`, стр. 619–625) все 5 конъюнктов `Inv_NoDeadlineRace` (`~((state="DRAFT") /\ t>=T /\ t<T)` и т.д.) являются **арифметическими тавтологиями** (всегда истинными в любой FSM!). Статус `PROVEN-IN-MODEL` по этим прогонам **ОТЗЫВАЕТСЯ**.
   - Единственная непустая проверка гонок дедлайнов в `v0.2` — `Inv_NoSimultaneousEnablement` в [`replay_5_deadline_race.log`](../v0.2/01_fsm/logs/replay_5_deadline_race.log) (`19 560` сост., где `ENABLED` для `Start/Confirm/OpenDispute/Appeal` сработали `16–672` раз), но и она **нечувствительна к мутациям действий**, пока `ENABLED` зашит на базовое имя действия (`v0.3` `mutant_1`).
3. **Уточнение в `v0.3`:** в [`NoKingV03.tla`](../v0.3/01_fsm/NoKingV03.tla) строки `654–655` `Inv_NoDeadlineRace` оставались тавтологическими, а **реальную защиту** обеспечили только добавленные после поломки `mutant_1` строки `656–657` (`submit_time < Deadline` — антецедент сработал `115 620` раз; `dispute_open_t < submit_time + T_review` — `9 660` раз в `v03_panel5.log`), а также `Inv_N08CancelGrace` не имел мутанта в v0.3 (проверен мутантом `mutant_11` только в v0.4).

### 2. Полная таблица нетривиальности инвариантов `v0.4` (`NoKingV04.tla` и `NoKingV04_TwoDeals.tla`)
По данным `-coverage 1` (вставляются точные числа срабатывания антецедентов из финального прогона `v04_base.log` / `v04_panel5.log` и `twodeals_v04.log`) и мутационного набора `mutant_1..12`:

| Инвариант / свойство `v0.4` | Сработал ли антецедент? (по логам TLC) | Какая мутация / состояние его опровергает | Вердикт нетривиальности |
|---|---|---|---|
| `Inv_Conservation`, `Inv_NonNegativeBalances` | Безусловные тождества на всех состояниях | Несбалансированный расход / сжигание USDC (`v0.1 lit_3`, `v0.3 M5`) | **Нетривиален** |
| `Inv_NoDoublePayout`, `Inv_EscrowIntactNonTerminal`, `Inv_EscrowEmptyTerminal` | В `v04_panel5.log` нетерминальные и терминальные антецеденты достижимы (`305 424` разл. сост.) | **`mutant_9` (`M9_DoublePayoutInAppealable`)** — убит на `5 105` сост. | **Нетривиален** |
| `Inv_NoZeroVoteWin` | Ветки `FOR_A`/`FOR_B` в `APPEALABLE`/`RESOLVED` достижимы в `v04_panel5.log` | **`mutant_10` (`M10_RevealZeroVoteBug`)** — убит на `5 150` сост. | **Нетривиален** |
| `Inv_NoDeadlineRace` *(без тавтологий!)* & `Inv_NoSimultaneousEnablement` | `submit_time >= 0`, `dispute_open_t >= 0`, `cancel_req_t >= 0` достижимы в `v04_panel5.log` | **`mutant_8` (`M8_RemoveDeadlineInSubmit`)** — убит на `1 193` сост. | **Нетривиален** |
| `Inv_F1SplitOnlyAfterChain`, `Inv_E1Round2NeverSplits5050` | В `v04_panel5.log`: `SPLIT_50_50` сработал **`2 220` раз**, `round=2 /\ RESOLVED` — **`18 600` раз** (`twodeals`: `2 308` сплитов!) | **`mutant_1` (`M1_DropF1Escalation`)** (`453` сост.) и **`mutant_3` (`M3_R2TimeoutSplit5050`)** (`59 876` сост.) | **Нетривиален** |
| `Inv_F1GrowingReward` | В `v04_panel5.log`: `DISPUTE /\ round=1` сработал **`18 060` раз** (`EscalateLevel`: `6 180` переходов) | **`mutant_2` (`M2_EscalateFlatReward`)** — убит на `444` сост. | **Нетривиален** |
| `Inv_F2AmountWithinProtocolMax` | Проверка параметров `e_create` на входе | **`mutant_5` (`M5_InitNoVMax` с `Amount=9000`)** — убит на старте (`02s`) | **Нетривиален** |
| `Inv_F3TallySealedUntilQuorum` | В `v04_panel5.log` антецедент некворумных состояний сработал **`133 140` раз** | **`mutant_4` (`M4_LeakTallyRedraw`)** — убит на `5 120` сост. | **Нетривиален** |
| `Inv_F4FeeToKeeperOnlyOnReviewTimeout` | В `v04_panel5.log`: `f4_review_fee_to_keeper` сработал **`160` раз** (в `twodeals`: `286` раз `CloseReview` → `balKeeper`) | **`mutant_6` (`M6_FinalizeToKeeper`)** — убит на `17 994` сост. | **Нетривиален** |
| `Inv_F5DefaultOnlyOnSellerTimeout` | В `v04_panel5.log`: `deadline_defaults > 0` (**`16` раз**), прочие состояния (`305 360`), `cancel_req /\ EXPIRED` (`32` раза); в `twodeals`: `992` сост. | **`mutant_7` (`M7_DefaultOnReviewTimeout`)** — убит на `742` сост. | **Нетривиален** |
| `Inv_M09CancelGraceAndDelay` | В `v04_panel5.log`: ранний `EXPIRED` до `T_accept` достигнут **`16` раз** (`ExecuteCancelDraft`: `16`) | **`mutant_11` (`M11_InstantCancelNoGrace`)** — убит на `22` сост. | **Нетривиален** |
| `Prop_EventuallyTerminal`, `Prop_DisputeAndAppealableExit` | Все терминальные состояния достижимы под `WF_vars(Next)` | **`mutant_12` (`M12_DropTimeoutsDeadlock`)** — `Deadlock reached` на `6 160` сост. | **Нетривиален** |

---

## X0.5 Мутационное тестирование (`12/12` мутантов убиты, [`NoKingV04_Mutants.tla`](01_fsm/NoKingV04_Mutants.tla))

Все 10 обязательных мутаций из задания + 2 дополнительные проверены в TLC и перехвачены в [`01_fsm/logs/`](01_fsm/logs/):

| # | Мутация | Нарушение, внесённое в модель | Нарушенный инвариант / свойство | Состояния (сген. / разл.) | Время | Лог |
|---|---|---|---|---|---|---|
| `mutant_1` | `M1_DropF1Escalation` | Удалена цепочка эскалации F1 (мгновенный 50/50 split на `esc_level=0`) | `Inv_F1SplitOnlyAfterChain` | `453 / 376` | `03s` | [`mutant_1.log`](01_fsm/logs/mutant_1.log) |
| `mutant_2` | `M2_EscalateFlatReward` | При эскалации награда `curr_reward` не растёт | `Inv_F1GrowingReward` | `444 / 368` | `03s` | [`mutant_2.log`](01_fsm/logs/mutant_2.log) |
| `mutant_3` | `M3_R2TimeoutSplit5050` | Разрешён возврат к D3 50/50 split в раунде 2 | `Inv_F1SplitOnlyAfterChain` | `59 876 / 49 997` | `23s` | [`mutant_3.log`](01_fsm/logs/mutant_3.log) |
| `mutant_4` | `M4_LeakTallyRedraw` | `RedrawPanel` раскрывает промежуточный счёт до `Q_arb` | `Inv_F3TallySealedUntilQuorum` | `5 120 / 4 155` | `10s` | [`mutant_4.log`](01_fsm/logs/mutant_4.log) |
| `mutant_5` | `M5_InitNoVMax` | Отключена проверка `Amount ≤ V_protocol_max` (`Amount=9000`) | `Inv_F2AmountWithinProtocolMax` | `Init` (сразу FALSE) | `02s` | [`mutant_5.log`](01_fsm/logs/mutant_5.log) |
| `mutant_6` | `M6_FinalizeToKeeper` | `protocol_fee` при споре отдаётся киперу | `Inv_F4FeeToKeeperOnlyOnReviewTimeout` | `17 994 / 15 356` | `13s` | [`mutant_6.log`](01_fsm/logs/mutant_6.log) |
| `mutant_7` | `M7_DefaultOnReviewTimeout` | Таймаут `REVIEW` (покупатель) засчитывает срыв продавцу | `Inv_F5DefaultOnlyOnSellerTimeout` | `742 / 612` | `03s` | [`mutant_7.log`](01_fsm/logs/mutant_7.log) |
| `mutant_8` | `M8_SubmitNoDeadline` | Убрана проверка `t_now < Deadline` в `Submit` | `Inv_NoDeadlineRace` | `1 193 / 1 017` | `04s` | [`mutant_8.log`](01_fsm/logs/mutant_8.log) |
| `mutant_9` | `M9_DoublePayoutInAppealable` | Ранняя выплата `Amount` при входе в `APPEALABLE` | `Inv_EscrowIntactNonTerminal` | `5 105 / 4 141` | `15s` | [`mutant_9.log`](01_fsm/logs/mutant_9.log) |
| `mutant_10` | `M10_RevealZeroVoteBug` | Возвращён баг `Def 5.2` (победа `FOR_B` при 0 голосов) | `Inv_NoZeroVoteWin` | `5 150 / 4 179` | `09s` | [`mutant_10.log`](01_fsm/logs/mutant_10.log) |
| `mutant_11` | `M11_InstantCancelNoGrace` | Отмена в `DRAFT` с `t_now=0` без grace/delay (`M-09`) | `Inv_M09CancelGraceAndDelay` | `22 / 22` | `02s` | [`mutant_11.log`](01_fsm/logs/mutant_11.log) |
| `mutant_12` | `M12_DropTimeoutsDeadlock` | Удалены таймауты `TimeoutR1Split5050` и `TimeoutR2KeepR1` | `Deadlock reached` | `6 160 / 5 037` | `09s` | [`mutant_12.log`](01_fsm/logs/mutant_12.log) |

---

## X0.6 Многосделочная модель v0.4 ([`NoKingV04_TwoDeals.tla`](01_fsm/NoKingV04_TwoDeals.tla))

Построена и исчерпывающе проверена модель **2 конкурентных сделок (`Deals = {1, 2}`)** с общими кошельками `balA, balB`, общим `balKeeper`, казной `balTreasury`, общим резервом наград эскалации `escReserve` и **конкуренцией за ограниченную ликвидность арбитров** (`InitArb = 60`, `PanelCost = 30`, поэтому 2 одновременных спора или R1+R2-удержание вызывают голодание `balArb < 30` и принудительную эскалацию `EscalateDeal`):
- **Границы:** `Amount = 100`, `SellerDeposit = 10`, `PanelSize = 3`, `ArbStake = 10`, `InitBuyer = 400`, `InitSeller = 400`, `InitArb = 60`, `InitReserve = 20`, `MaxTime = 11`.
- **Результат ([`twodeals_v04.log`](01_fsm/logs/twodeals_v04.log)):** `232 854` сгенерированных / **`141 314` различных состояний**, глубина `29`, `01m 00s`, **`0` ошибок (`PROVEN-IN-MODEL` в границах модели)**. Покрыты все переходы, включая `EscalateDeal` (`2075:2660`), `CloseReview` Confirm (`176`) & Keeper Timeout (`286`), оба исхода `FinalizeOrResolveR2` (`5858:6860` и `40463:45216`) и оба типа `TimeoutDispute` (`7442:15154`).
