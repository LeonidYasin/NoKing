# V2. Формальная модель TLA+ и верификация NoKing v0.2

## 1. Модели, инструмент и границы

- **Инструмент:** `TLC2 Version 2.19 of 08 August 2024` (OpenJDK 17.0.21.1).
- **Основная модель v0.2:** [`NoKingV02.tla`](NoKingV02.tla) — формализует [`exchange-spec-v0.2.md`](../../../protocol/specs/exchange-spec-v0.2.md), включая D1–D7, D9-A/D9-B, D10, `commit-reveal`, `APPEALABLE`, `e_redraw` и `T_dispute_max` компромисс.
- **Реплей-модуль:** [`NoKingV02_Replays.tla`](NoKingV02_Replays.tla) — повторяет 6 сценариев-контрпримеров из v0.1 и проверяет невозможность их воспроизведения.
- **Многосделочная модель (V2.4):** [`NoKingV02_TwoDeals.tla`](NoKingV02_TwoDeals.tla) — 2 параллельные асинхронные сделки с общими кошельками, казной, `pool_ok` и отказами.

### Размеры проверенных моделей
1. **`v02_d9a.cfg` (Денежная сделка D9-A, с перевыбором `e_redraw`):** `Amount = 100`, `SellerDeposit = 10`, `BuyerDeposit = 0`, `PanelSize = 3`, `Q_arb = 2`, `T_dispute_max = 5`, `MaxTime = 16`.
2. **`v02_d9b.cfg` (Бартер с взаимным депозитом D9-B):** `Amount = 0`, `SellerDeposit = 10`, `BuyerDeposit = 10`, `ProtocolFee = 0`, `PanelSize = 3`, `Q_arb = 2`, `T_dispute_max = 5`, `MaxTime = 16`.
3. **`v02_panel5.cfg` (Коллегия `k = 5`, `Q_arb = 3`):** `PanelSize = 5`, `Q_arb = 3`, `T_dispute_max = 3`, `MaxTime = 14`.
4. **`twodeals.cfg` (2 параллельные сделки):** `Deals = {1, 2}`, `PanelSize = 3`, `Q_arb = 2`, `MaxTime = 10`.

---

## 2. Сводная таблица прогонов TLC

| Конфигурация | Сгенерировано состояний | Различных состояний | Глубина | Время | Результат | Лог |
|---|---|---|---|---|---|---|
| `v02_d9a.cfg` (D9-A + перевыбор) | `485 700` | `322 968` | `44` | `01m 57s` | **0 ошибок** (`PROVEN-IN-MODEL`) | [`v02_d9a.log`](logs/v02_d9a.log) |
| `v02_d9b.cfg` (D9-B бартер) | `485 764` | `323 000` | `44` | `01m 54s` | **0 ошибок** (`PROVEN-IN-MODEL`) | [`v02_d9b.log`](logs/v02_d9b.log) |
| `v02_panel5.cfg` (`k = 5, Q_arb = 3`) | `30 588` | `19 560` | `25` | `15s` | **0 ошибок** (`PROVEN-IN-MODEL`) | [`v02_panel5.log`](logs/v02_panel5.log) |
| `twodeals.cfg` (2 сделки) | `61 053` | `36 144` | `24` | `11s` | **0 ошибок** (`PROVEN-IN-MODEL`) | [`twodeals.log`](logs/twodeals.log) |

**Покрытие (`-coverage 1`):** в `v02_d9a` и `v02_d9b` сработали все 21 действие (`Accept`, `CancelDraftByA`, `TimeoutDraft`, `Start`, `TimeoutLocked`, `Submit`, `TimeoutInProgress`, `Confirm`, `TimeoutReview`, `OpenDispute`, `FormPanel`, `CommitVotes`, `RevealVotes`, `RedrawPanel`, `DisputeTimeoutCompromise`, `ResolveRound1ToAppealable`, `Appeal`, `FinalizeAppealable`, `ResolveRound2Final`, `TerminalStutter`). Мёртвых переходов и недостижимых состояний в модели нет.

---

## 3. Повторное проигрывание всех 6 контрпримеров v0.1

Каждый сценарий, который давал ошибку в v0.1 (`NoKingLiteral.tla`), повторён на `NoKingV02_Replays.tla` (`PanelSize = 5, Q_arb = 3`):

| # | Контрпример v0.1 | Проверяемый инвариант / свойство в v0.2 | Покрытие триггера в логе | Результат в v0.2 | Лог v0.2 |
|---|---|---|---|---|---|
| 1 | `lit_double_payout.log` (двойная выплата при апелляции) | `Inv_NoDoublePayout`, `Inv_AppealSafety`, `Inv_Conservation` | `Appeal` (`384:672`), `ResolveRound2Final` (`1008:5376`), `FinalizeAppealable` (`336:336`) | **Не воспроизводится** (`19 560` сост., 0 ошибок) | [`replay_1_double_payout.log`](logs/replay_1_double_payout.log) |
| 2 | `lit_trapped_funds.log` (зависание при `e_cancel` / штрафе `Penalty_i`) | `Inv_Conservation`, `Inv_EscrowEmptyTerminal` | `CancelDraftByA` (`8:8`), неединогласные `RevealVotes` | **Не воспроизводится** (`19 560` сост., 0 ошибок) | [`replay_2_trapped_funds.log`](logs/replay_2_trapped_funds.log) |
| 3 | `lit_burned_usdc.log` (сжигание USDC при `FOR_B`) | `Inv_Conservation`, `Inv_NonNegativeBalances`, `Inv_EscrowEmptyTerminal` | Ветка `FOR_B` в `FinalizeAppealable` и `ResolveRound2Final` | **Не воспроизводится** (`19 560` сост., 0 ошибок) | [`replay_3_burned_usdc.log`](logs/replay_3_burned_usdc.log) |
| 4 | `lit_zero_vote.log` (победа `FOR_B` при 0 голосов) | `Inv_NoZeroVoteWin`, `Inv_NoZeroVoteForB` | `RevealVotes` перебирает все тройки `(va, vb, vunrev)` включая `votesB=0` | **Не воспроизводится** (`19 560` сост., 0 ошибок) | [`replay_4_zero_vote.log`](logs/replay_4_zero_vote.log) |
| 5 | `lit_deadline_race.log` (гонка дедлайнов) | `Inv_NoDeadlineRace`, `Inv_NoSimultaneousEnablement` (`~(ENABLED Active /\ ENABLED Timeout)`) | Все 5 дедлайн-переходов проверены через `ENABLED` | **Не воспроизводится** (`19 560` сост., 0 ошибок) | [`replay_5_deadline_race.log`](logs/replay_5_deadline_race.log) |
| 6 | `lit_liveness.log` (deadlock в `DISPUTE` при `|E|<15`) | `Prop_EventuallyTerminal`, `Prop_DisputeAndAppealableExit` при `InitSmallPool` (`pool_sufficient=FALSE`) | `DisputeTimeoutCompromise` сработал до выхода в `RESOLVED` | **Не воспроизводится** (`276` сост., 0 ошибок) | [`replay_6_liveness.log`](logs/replay_6_liveness.log) |

---

## 4. Воспроизведение

```bash
cd verification/v0.2/01_fsm
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -config v02_d9a.cfg NoKingV02.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -config v02_d9b.cfg NoKingV02.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -config v02_panel5.cfg NoKingV02.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -config twodeals.cfg NoKingV02_TwoDeals.tla
```
