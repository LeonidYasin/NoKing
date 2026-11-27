# T1. Формальная модель FSM и Model Checking (TLA+ / TLC)

## 1. Инструмент, модели и границы проверки

- **Инструмент:** `TLC2 Version 2.19 of 08 August 2024` (TLA+ model checker, OpenJDK 17.0.21.1).
- **Модель 1 (буквальная спецификация):** [`NoKingLiteral.tla`](NoKingLiteral.tla) — формализует `exchange-spec.md` максимально буквально, включая все выявленные в [`00_audit.md`](../00_audit.md) пробелы и противоречия.
- **Модель 2 (исправленная спецификация):** [`NoKingFixed.tla`](NoKingFixed.tla) — добавляет промежуточное состояние `APPEALABLE`, верхние временные ограничения на дедлайны, кворум большинства, резервный таймаут `DISPUTE`, маршрутизацию штрафов без «сжигания» USDC и атомарную блокировку депозита при `e_accept`.
- **Границы bounded-модели:** 1 соглашение (`Amount = 100`, `SellerDeposit = 10`, `Penalty = 5`, `ProtocolFee = 1`, `DisputeDeposit = 5`, `AppealDeposit = 15`, `ArbStake = 10`, `ArbPenalty = 2`), абстрактная коллегия `PanelSize = 3` (представляет нечётное `k`), дискретное время `t_now ∈ 0..MaxTime` (`T_accept = 2`, `Deadline = 4`, `T_review = 2`, `T_evidence = 2`, `T_vote = 2`, `T_appeal = 2`, `MaxTime = 16` в Literal / `18` в Fixed). Проверка не распространяется на многоэтапные сделки (`Milestone` Sub-FSM в спецификации не описан) и многоконтрактное взаимодействие `keeper_pool`.

### Воспроизведение

```bash
cd verification/01_fsm
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -config lit_double_payout.cfg NoKingLiteral.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -config fixed_all.cfg NoKingFixed.tla
```

*(Примечание: `tla2tools.jar` скачивается с `https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar`.)*

---

## 2. Сводная таблица результатов проверки

| Свойство | Модель `NoKingLiteral` | Модель `NoKingFixed` | Артефакт / Контрпример |
|---|---|---|---|
| **Conservation (баланс средств)** | `PROVEN-IN-MODEL` *(только при явном учёте `trappedFunds` и `burnedFunds`)* | `PROVEN-IN-MODEL` *(33 932 различных состояния, `trapped = 0`, `burned = 0`)* | [`fixed_all.log`](logs/fixed_all.log) |
| **No Double Payout (запрет двойной выплаты)** | **`FALSIFIED`** *(апелляция после `RESOLVED` пытается выплатить `Amount` повторно)* | `PROVEN-IN-MODEL` *(`payout_count ≤ 1` во всех 33 932 состояниях)* | [`lit_double_payout.log`](logs/lit_double_payout.log) |
| **No Trapped Funds (отсутствие зависших средств)** | **`FALSIFIED`** *(`e_cancel` в `DRAFT` и `Penalty_i` арбитров без получателя)* | `PROVEN-IN-MODEL` *(все балансы неотрицательны, 0 зависших средств)* | [`lit_trapped_funds.log`](logs/lit_trapped_funds.log) |
| **No Burned Stablecoin (корректность расчётов в ERC-20)** | **`FALSIFIED`** *(`FOR_B` сжигает `(1-σ)·seller_deposit = 5` в USDC)* | `PROVEN-IN-MODEL` *(остаток направляется в `Treasury`)* | [`lit_burned_usdc.log`](logs/lit_burned_usdc.log) |
| **Честность большинства (`Inv_NoZeroVoteBuyerWin`)** | **`FALSIFIED`** *(`votesA=1, votesB=0, votesAbstain=2` → побеждает `FOR_B` при 0 голосов!)* | `PROVEN-IN-MODEL` *(требуется кворум `votesA + votesB > k/2`)* | [`lit_zero_vote.log`](logs/lit_zero_vote.log) |
| **Согласованность (отсутствие гонок дедлайнов)** | **`FALSIFIED`** *(при `t_now ≥ submit_time + T_review` одновременно допустимы `e_timeout` и `e_dispute`)* | `PROVEN-IN-MODEL` *(строгие верхние границы времени)* | [`lit_deadline_race.log`](logs/lit_deadline_race.log) |
| **Liveness (`Prop_EventuallyTerminal`)** | **`FALSIFIED`** *(deadlock в `DISPUTE` при `|E| < 3k`, т.е. `pool_sufficient = FALSE`)* | `PROVEN-IN-MODEL` *(все трассы достигают `CLOSED`/`EXPIRED`/`RESOLVED`)* | [`lit_liveness.log`](logs/lit_liveness.log) |
| **Достижимость состояний и переходов** | `UNVERIFIED` *(в `NoKingLiteral` поиск останавливается на ошибках безопасности)* | `PROVEN-IN-MODEL` *(по `-coverage 1` все 20 действий и `Init` сработали, 0 мёртвых переходов)* | [`fixed_all.log`](logs/fixed_all.log) |

---

## 3. Описание контрпримеров TLC (трассы воспроизведения)

### 3.1 `Inv_NoDoublePayout` — `FALSIFIED` ([`lit_double_payout.log`](logs/lit_double_payout.log))
- **Трасса (16 шагов, 14 240 различных состояний):**
  `DRAFT` (State 1) → `Accept` → `LOCKED` → `Start` → `IN_PROGRESS` → `SubmitFake` → `REVIEW` → `OpenDispute` (`round = 1`) → `FormPanel` → `CastVotes` (`votesA = 3`) → `ResolveDispute` (State 10: `state = "RESOLVED"`, `payout_count = 1`, `escrowBuyer = 0`, `balA = 299`) → `Appeal` (State 11: `round = 2`, `state = "DISPUTE"`, `balB = 80`) → `FormPanel` → `CastVotes` (`votesA = 3`) → `ResolveDispute` (State 16: `escrowBuyer = 0 < Amount`, **`doublePayoutErr = TRUE`**).
- **Причина:** Раздел 3.3 объявляет `RESOLVED` терминальным состоянием и Раздел 5.5 предписывает выплату, тогда как Раздел 5.6 позволяет проигравшей стороне подать апелляцию в течение `T_appeal`.

### 3.2 `Inv_NoTrappedFunds` — `FALSIFIED` ([`lit_trapped_funds.log`](logs/lit_trapped_funds.log))
- **Трасса (2 шага, 10 различных состояний):**
  `DRAFT` (`DraftDepositAtCreate = TRUE`, `escrowSeller = 10`) → `CancelDraft` (State 2: `state = "EXPIRED"`, `escrowSeller = 0`, **`trappedFunds = 10`**).
- **Второй случай:** в [`lit_burned_usdc.log`](logs/lit_burned_usdc.log) State 10 при `votesA = 1, votesB = 2` штраф меньшинства `ArbPenalty = 2` не имеет получателя в спецификации (`trappedFunds = 2`).

### 3.3 `Inv_NoBurnedStablecoin` — `FALSIFIED` ([`lit_burned_usdc.log`](logs/lit_burned_usdc.log))
- **Трасса (10 шагов, 965 различных состояний):**
  `DRAFT` → `Accept` → `Start` → `SubmitFake` → `OpenDispute` → `FormPanel` → `CastVotes` (`votesA = 1, votesB = 2`) → `ResolveDispute` (State 10: победа `FOR_B`, `burnedFunds = 5`).
- **Причина:** Раздел 5.5 требует сжечь `(1 - σ)·seller_deposit` в стейблкоине `Agreement.token` (USDC), что невозможно без прав эмитента или безвозвратно уничтожает пользовательские USDC.

### 3.4 `Inv_NoZeroVoteBuyerWin` — `FALSIFIED` ([`lit_zero_vote.log`](logs/lit_zero_vote.log))
- **Трасса (10 шагов, 970 различных состояний):**
  `SubmitHonest` (`seller_delivered = TRUE`) → `OpenDispute` (`buyer_honest = FALSE`) → `CastVotes` (State 9: `votesA = 1, votesB = 0, votesAbstain = 2`) → `ResolveDispute` (State 10: условие `votesA > k/2` (`1 > 1.5`) ложно, поэтому Def. 5.2 выбирает `FOR_B` при **`votesB = 0`**, `balB = 205`, все 3 арбитра оштрафованы как меньшинство, `trappedFunds = 6`).

### 3.5 `Inv_NoDeadlineRace` — `FALSIFIED` ([`lit_deadline_race.log`](logs/lit_deadline_race.log))
- **Трасса (6 шагов, 108 различных состояний):**
  `SubmitHonest` (`submit_time = 0`) → `Tick` → `Tick` (State 6: `state = "REVIEW"`, `t_now = 2 ≥ submit_time + T_review`). В этом состоянии одновременно доступны и `TimeoutReview` (`→ CLOSED`), и `OpenDispute` (`→ DISPUTE`), что создаёт гонку транзакций (front-running) в мемпуле.

### 3.6 `Prop_EventuallyTerminal` (Liveness) — `FALSIFIED` ([`lit_liveness.log`](logs/lit_liveness.log))
- **Трасса (21 шаг, 128 761 состояние):**
  Инициализация с `pool_sufficient = FALSE` (`|E| < 3k = 15`) → `Accept` → `Start` → `SubmitHonest` → `OpenDispute` (State 21: `state = "DISPUTE"`, `escrowBuyer = 100`, `escrowSeller = 10`, `escrowDispute = 5`). Действие `FormPanel` заблокировано (`pool_sufficient = FALSE`), таймаут для `DISPUTE` в таблице 3.3 отсутствует → **Deadlock reached**, 115 USDC навсегда заблокированы в контракте.

---

## 4. Верификация исправленной модели (`NoKingFixed.tla`)

После внесения шести точечных исправлений в [`NoKingFixed.tla`](NoKingFixed.tla):
- **Результат TLC:** `Model checking completed. No error has been found.`
- **Объём исчерпывающего обхода:** `54 496` сгенерированных состояний, `33 932` различных состояния, глубина графа `30`, время `10 с`.
- **Покрытие переходов (`-coverage 1`):** все 20 действий (`Tick`, `Accept`, `TimeoutDraft`, `CancelDraft`, `Start`, `TimeoutLocked`, `SubmitHonest`, `SubmitFake`, `TimeoutInProgress`, `Confirm`, `TimeoutReview`, `OpenDispute`, `FormPanel`, `CastVotes`, `DisputeFallbackTimeout`, `ResolveToAppealable`, `Appeal`, `FinalizeAppealWindow`, `FinalizeRound2`, `TerminalStutter`) исполнились ненулевое число раз (например, `Appeal: 144:576`, `FinalizeRound2: 1152:1728`, `DisputeFallbackTimeout: 7944:12888`).
- **Статус:** для ограниченной модели с 1 сделкой и `PanelSize = 3` свойства **Safety**, **Liveness**, **Достижимость** и **Согласованность** имеют статус `PROVEN-IN-MODEL`.
