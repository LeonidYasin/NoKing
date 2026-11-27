# X2 & X0.5–X0.6. Формальные модели TLA+ (`NoKingV04`, `TwoDeals`, 12 мутантов)

## 1. Модели, инструмент и границы

- **Инструмент:** `TLC2 Version 2.19 of 08 August 2024` (OpenJDK `17.0.21.1`).
- **Модель 1 (1 сделка):** [`NoKingV04.tla`](NoKingV04.tla) — формализует [`exchange-spec-v0.4.md`](../../../protocol/specs/exchange-spec-v0.4.md): **F1** (3-уровневая эскалация R1 `esc_level 0→1→2` с растущей наградой `curr_reward = BaseArbReward + failed_attempts·EscBonus` из `escReserve`, 50/50 split только при `esc_level = 2`), **F2** (`Amount ≤ V_protocol_max`), **F3** (`tally_sealed = TRUE` до набора `Q_arb`), **F4** (100% `ProtocolFee` киперу на `TimeoutReview`), **F5** (`deadline_defaults` только на `TimeoutLocked`/`TimeoutInProgress`), а также `M-09` (`RequestCancelDraft` → `ExecuteCancelDraft`).
- **Модель 2 (2 конкурентные сделки, X0.6):** [`NoKingV04_TwoDeals.tla`](NoKingV04_TwoDeals.tla) — `Deals = {1, 2}` с общими кошельками `balA, balB`, общим `balKeeper`, `balTreasury`, `escReserve` и **ограниченной ликвидностью арбитров `InitArb = 60` (`PanelCost = 30`)**, вызывающей реальное межсделочное голодание (`EscalateDeal`) при одновременных спорах.
- **Модуль мутаций (X0.5):** [`NoKingV04_Mutants.tla`](NoKingV04_Mutants.tla) — 12 преднамеренных ошибок (`MutantId = 1..12`), включая все 10 обязательных мутаций задания + 2 дополнительные.

### Границы bounded-моделей
- **1 сделка (`v04_base.cfg`):** `Amount = 100`, `V_protocol_max = 8750`, `SellerDeposit = 10`, `Penalty = 5`, `ProtocolFee = 1`, `DisputeDeposit = 5`, `AppealDeposit = 15`, `DelayComp = 5`, `ArbStake = 20`, `ArbPenalty = 5`, `ArbUnrevPenalty = 10`, `BaseArbReward = 2`, `EscBonus = 2`, `KeeperFee = 1`, `PanelSize = 3`, `Q_arb = 2`, `T_cancel_grace = 1`, `T_cancel_delay = 1`, `T_accept = 2`, `Deadline = 4`, `T_review = 2`, `T_dispute_max = 4`, `T_appeal = 2`, `MaxTime = 16`, `InitReserve = 50`.
- **1 сделка (`v04_panel5.cfg`, реплеи/атаки):** `PanelSize = 5`, `Q_arb = 3`, `T_accept = 3`, `Deadline = 5`, `T_dispute_max = 3`, `MaxTime = 15`.
- **2 сделки (`twodeals_v04.cfg`):** `PanelSize = 3`, `ArbStake = 10`, `InitBuyer = 400`, `InitSeller = 400`, `InitArb = 60`, `InitReserve = 20`, `T_dispute_max = 3`, `MaxTime = 11`.

---

## 2. Таблица прогонов TLC на `NoKingV04` и `NoKingV04_TwoDeals`

| Конфигурация | Сгенерировано состояний | Различных состояний | Глубина | Время | Результат | Лог |
|---|---|---|---|---|---|---|
| [`v04_base.cfg`](v04_base.cfg) (`k=3, Q=2, T_dispute_max=4` с `RedrawPanel`) | `1 856 376` | `1 177 344` | `35` | `09m 35s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v04_base.log`](logs/v04_base.log) |
| [`v04_panel5.cfg`](v04_panel5.cfg) (`k=5, Q=3`, полный набор) | `497 650` | `305 424` | `28` | `02m 35s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v04_panel5.log`](logs/v04_panel5.log) |
| [`atk_v04.cfg`](atk_v04.cfg) (`N-01, N-03/05, M-01, M-03, M-10`) | `497 650` | `305 424` | `28` | `32s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/atk_v04.log`](logs/atk_v04.log) |
| [`replay_1_double_payout.cfg`](replay_1_double_payout.cfg) | `497 650` | `305 424` | `28` | `27s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_1_double_payout.log`](logs/replay_1_double_payout.log) |
| [`replay_2_trapped_funds.cfg`](replay_2_trapped_funds.cfg) | `497 650` | `305 424` | `28` | `29s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_2_trapped_funds.log`](logs/replay_2_trapped_funds.log) |
| [`replay_3_burned_usdc.cfg`](replay_3_burned_usdc.cfg) | `497 650` | `305 424` | `28` | `27s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_3_burned_usdc.log`](logs/replay_3_burned_usdc.log) |
| [`replay_4_zero_vote.cfg`](replay_4_zero_vote.cfg) | `497 650` | `305 424` | `28` | `26s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_4_zero_vote.log`](logs/replay_4_zero_vote.log) |
| [`replay_5_deadline_race.cfg`](replay_5_deadline_race.cfg) | `497 650` | `305 424` | `28` | `26s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_5_deadline_race.log`](logs/replay_5_deadline_race.log) |
| [`replay_6_liveness.cfg`](replay_6_liveness.cfg) (`InitAllPoolsEmpty`, L0=L1=L2=FALSE) | `1 476` | `1 068` | `16` | `05s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_6_liveness.log`](logs/replay_6_liveness.log) |
| [`twodeals_v04.cfg`](twodeals_v04.cfg) (2 конкурентные сделки, `InitArb=60`) | `232 854` | `141 314` | `29` | `01m 00s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/twodeals_v04.log`](logs/twodeals_v04.log) |

*(По совокупности прогонов `v04_base.log` (`RedrawPanel: 30624:30624`, `EscalateLevel: 5232:11952`, `TimeoutR1Split5050: 4224:4224`, `ExecuteCancelDraft: 0:0` из-за `T_accept = T_cancel_grace + T_cancel_delay = 2`) и `v04_panel5.log` (`ExecuteCancelDraft: 16:16`, `RedrawPanel: 0:0` из-за `T_dispute_max = 3`) подтверждены **все 23 из 23 действий `Next` плюс `Init`**; в `twodeals_v04.log` сработали все действия, включая `EscalateDeal: 2075:2660` и обе ветки `FinalizeOrResolveR2`: `5858:6860` и `40463:45216`.)*

---

## 3. Результаты мутационного тестирования (`12/12` убито, [`NoKingV04_Mutants.tla`](NoKingV04_Mutants.tla))

Сводная таблица — в [`X0_methodology.md`](../X0_methodology.md) (`X0.5`): все 12 мутаций (`M1_DropF1Escalation`, `M2_EscalateFlatReward`, `M3_R2TimeoutSplit5050`, `M4_LeakTallyRedraw`, `M5_InitNoVMax`, `M6_FinalizeToKeeper`, `M7_DefaultOnReviewTimeout`, `M8_SubmitNoDeadline`, `M9_DoublePayoutInAppealable`, `M10_RevealZeroVoteBug`, `M11_InstantCancelNoGrace`, `M12_DropTimeoutsDeadlock`) перехвачены TLC за `02s–23s` каждая.

---

## 4. Воспроизведение

```bash
cd verification/v0.4/01_fsm
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v04/p5 -config v04_panel5.cfg NoKingV04.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v04/base -config v04_base.cfg NoKingV04.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v04/td -config twodeals_v04.cfg NoKingV04_TwoDeals.tla
for m in $(seq 1 12); do
  java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -metadir /tmp/tlc_meta_v04/m${m} -config mutant_${m}.cfg NoKingV04_Mutants.tla
done
```
