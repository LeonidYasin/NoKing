# W2 & W0.4. Формальная модель TLA+ и мутационное тестирование (`v0.3`)

## 1. Модели, инструмент и границы проверки

- **Инструмент:** `TLC2 Version 2.19 of 08 August 2024` (OpenJDK `17.0.21.1`).
- **Основная модель v0.3:** [`NoKingV03.tla`](NoKingV03.tla) — формализует [`exchange-spec-v0.3.md`](../../../protocol/specs/exchange-spec-v0.3.md), включая:
  - **E1:** в раунде 1 при срыве пула/кворума сначала эскалация в `Category.parent` (`EscalateToParent`), затем 50/50 split с потерей `D_dispute` обеими сторонами (`TimeoutR1Split5050`); в раунде 2 при провале сохраняется вердикт раунда 1 (`TimeoutR2KeepR1`) с возвратом только `appeal_deposit`.
  - **E3:** штраф `ArbUnrevPenalty` за `UNREVEALED` отдельно от `ArbPenalty` меньшинства; `RedrawPanel` добирает только недостающие места (`k - (votesA + votesB)`), сохраняя раскрытые голоса.
  - **E4/E5:** только денежные сделки (`Amount > 0`), без D9-B; киперы в `EXPIRED` / `REVIEW` получают `KeeperFee`.
  - **Доп. предложения:** симметризация премии арбитров при `FOR_B` (остаток `escrowSeller - Penalty` направляется арбитрам, а не в казну), компенсация задержки `DelayComp` (`N-04`) при отклонении апелляции, период `T_cancel_grace` для `CancelDraftByA` в `DRAFT` (`N-08`).
- **Модуль мутационного тестирования (W0.4):** [`NoKingV03_Mutants.tla`](NoKingV03_Mutants.tla) (`EXTENDS NoKingV03`, 6 преднамеренных ошибок `MutantId = 1..6` + инициализация `InitAllPoolsEmpty` для проверки `replay_6_liveness`).

### Границы bounded-модели
- **1 сделка:** `Amount = 100`, `SellerDeposit = 10`, `Penalty = 5`, `ProtocolFee = 1`, `DisputeDeposit = 5`, `AppealDeposit = 15`, `DelayComp = 5`, `ArbStake = 20`, `ArbPenalty = 5`, `ArbUnrevPenalty = 10`, `KeeperFee = 1`, `InitBuyer = 200`, `InitSeller = 200`, `InitArb = 400`.
- **Конфигурация `v03_base.cfg` (с добором `e_redraw`):** `PanelSize = 3`, `Q_arb = 2`, `T_cancel_grace = 1`, `T_accept = 2`, `Deadline = 4`, `T_review = 2`, `T_evidence = 1`, `T_commit = 1`, `T_reveal = 1`, `T_dispute_max = 4`, `T_appeal = 2`, `MaxTime = 16`. В ней сработали **все 23 действия `Next` и `Init`** (`RedrawPanel: 11808:11808`).
- **Конфигурация `v03_panel5.cfg` (и реплеи/атаки):** `PanelSize = 5`, `Q_arb = 3`, `T_cancel_grace = 1`, `T_accept = 3`, `Deadline = 5`, `T_review = 2`, `T_evidence = 1`, `T_commit = 1`, `T_reveal = 1`, `T_dispute_max = 3`, `T_appeal = 2`, `MaxTime = 15`. В ней сработали 22 из 23 действий `Next` (`RedrawPanel: 0:0`, т.к. `T_dispute_max = T_evidence + T_commit + T_reveal = 3`).
- **Ограничения абстракции:** не моделируются многосделочный параллелизм в одном запуске v0.3, криптография VRF / Sortition Sum-Tree и динамический расчёт репутации.

---

## 2. Таблица прогонов TLC на `NoKingV03.tla`

| Конфигурация | Сгенерировано состояний | Различных состояний | Глубина | Время | Результат | Лог |
|---|---|---|---|---|---|---|
| [`v03_base.cfg`](v03_base.cfg) (`k=3, Q=2, T_dispute_max=4`, полный набор инвариантов + Liveness + `RedrawPanel`) | `507 680` | `339 184` | `36` | `02m 18s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v03_base.log`](logs/v03_base.log) |
| [`v03_panel5.cfg`](v03_panel5.cfg) (`k=5, Q=3`, полный набор инвариантов + Liveness) | `183 942` | `115 788` | `27` | `01m 00s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v03_panel5.log`](logs/v03_panel5.log) |
| [`atk_n01_n03_n04_n08.cfg`](atk_n01_n03_n04_n08.cfg) (проверка атак N-01, N-03/05, N-04, N-08) | `183 942` | `115 788` | `27` | `14s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/atk_n01_n03_n04_n08.log`](logs/atk_n01_n03_n04_n08.log) |
| [`replay_1_double_payout.cfg`](replay_1_double_payout.cfg) | `183 942` | `115 788` | `27` | `14s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_1_double_payout.log`](logs/replay_1_double_payout.log) |
| [`replay_2_trapped_funds.cfg`](replay_2_trapped_funds.cfg) | `183 942` | `115 788` | `27` | `16s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_2_trapped_funds.log`](logs/replay_2_trapped_funds.log) |
| [`replay_3_burned_usdc.cfg`](replay_3_burned_usdc.cfg) | `183 942` | `115 788` | `27` | `12s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_3_burned_usdc.log`](logs/replay_3_burned_usdc.log) |
| [`replay_4_zero_vote.cfg`](replay_4_zero_vote.cfg) | `183 942` | `115 788` | `27` | `12s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_4_zero_vote.log`](logs/replay_4_zero_vote.log) |
| [`replay_5_deadline_race.cfg`](replay_5_deadline_race.cfg) | `183 942` | `115 788` | `27` | `15s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_5_deadline_race.log`](logs/replay_5_deadline_race.log) |
| [`replay_6_liveness.cfg`](replay_6_liveness.cfg) (`InitAllPoolsEmpty`, оба пула пусты) | `408` | `312` | `15` | `03s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_6_liveness.log`](logs/replay_6_liveness.log) |

*(В [`logs/v03_base.log`](logs/v03_base.log) подтверждена работа **всех 23 действий `Next` и `Init`** (`Accept` `14:16`, `CancelDraftByA` `8:8`, `TimeoutDraft` `8:8`, `Start` `31:32`, `TimeoutLocked` `16:16`, `Submit` `64:64`, `TimeoutInProgress` `0:16`, `Confirm` `32:32`, `TimeoutReview` `64:64`, `OpenDispute` `96:128`, `FormPanel` `31240:37392`, `EscalateToParent` `1008:2016`, `CommitVotes` `14760:14760`, `RevealVotes` `94464:103320`, **`RedrawPanel` `11808:11808`**, `TimeoutR1Split5050` `1968:1968`, `TimeoutR2KeepR1` `23328:77760`, `ResolveRound1ToAppealable` `1440:1440`, `Appeal` `2880:4320`, `FinalizeAppealable` `1440:1440`, `ResolveRound2Final` `17280:57600`, `TerminalStutter` `0:44144`).)*

---

## 3. Сценарии атак `N-01, N-03/05, N-04, N-08` на модели v0.3

- **`N-01` (абуз апелляции в раунде 2):** инвариант `Inv_E1Round2NeverSplits5050` и `Inv_N01Round2NoBuyerProfit` проверены на всех `115 788` состояниях (`atk_n01_n03_n04_n08.log`). При провале раунда 2 (`TimeoutR2KeepR1`) вердикт `FOR_A` остаётся в силе, покупатель не получает возврат `Amount`, а получает назад только `AppealDeposit`.
- **`N-03 / N-05` (саботаж `UNREVEALED` и добор мест):** `RevealVotes` перебирает все распределения `(dA, dB, dUnrev)`; `Inv_NoZeroVoteWin` и `Prop_DisputeAndAppealableExit` гарантируют невозможность победы при `0` голосов и гарантированный выход из `DISPUTE` по `e_escalate` / E1-таймауту даже при саботаже раскрытия.
- **`N-04` (задержка в `APPEALABLE`):** при отклонении апелляции в `ResolveRound2Final` флаг `n04_delay_paid` становится `TRUE` и победитель раунда 1 получает `DelayComp` (`5` из `AppealDeposit = 15`).
- **`N-08` (`T_cancel_grace` в `DRAFT`):** `Inv_N08CancelGrace` подтверждает во всех `115 788` состояниях, что `CancelDraftByA` не может перевести сделку в `EXPIRED` при `t_now < T_cancel_grace`. *(Остаточный риск фронтраннинга при `t_now ≥ T_cancel_grace` зафиксирован в `05_attacks.md` как `M-09`.)*

---

## 4. Мутационное тестирование модели (`W0.4`)

В [`NoKingV03_Mutants.tla`](NoKingV03_Mutants.tla) реализованы 6 намеренных ошибок, имитирующих типичные баги спецификации:

| Мутация | Внесённая ошибка | Первый прогон | Финальный результат после доработки инварианта | Нарушенное свойство / состояния | Лог |
|---|---|---|---|---|---|
| **`mutant_1`** (`M1_RemoveDeadlineGuard`) | Снята проверка `t_now < Deadline` в `Submit` | **ВЫЖИЛА** (`43 944` сост., 0 ошибок — `Inv_NoSimultaneousEnablement` проверял базовый `Submit`, а не `M1_Submit`! См. [`logs/mutant_1_survived_before_fix.log`](logs/mutant_1_survived_before_fix.log)) | **УБИТА** (усилен `Inv_NoDeadlineRace`: `submit_time < Deadline` и `dispute_open_t < submit_time + T_review`) | `Inv_NoDeadlineRace` (`884` сген. / `712` разл., глубина `9`, `03s`) | [`logs/mutant_1.log`](logs/mutant_1.log) |
| **`mutant_2`** (`M2_DoublePayoutInAppealable`) | Ранняя выплата `Amount` при переходе в `APPEALABLE` | **УБИТА** | **УБИТА** | `Inv_EscrowIntactNonTerminal` (`1 820` сген. / `1 446` разл., глубина `11`, `04s`) | [`logs/mutant_2.log`](logs/mutant_2.log) |
| **`mutant_3`** (`M3_RestoreZeroVoteWin`) | Возвращён баг Def. 5.2 v0.1 (`FOR_A` при `2·vA > k`, иначе `FOR_B`) | **УБИТА** | **УБИТА** | `Inv_NoZeroVoteWin` (`1 856` сген. / `1 483` разл., глубина `11`, `04s`) | [`logs/mutant_3.log`](logs/mutant_3.log) |
| **`mutant_4`** (`M4_DropE1Timeout`) | Удалены `TimeoutR1Split5050` и `TimeoutR2KeepR1` | **УБИТА** | **УБИТА** | `Deadlock reached` (`1 044` сген. / `824` разл., глубина `9`, `03s`) | [`logs/mutant_4.log`](logs/mutant_4.log) |
| **`mutant_5`** (`M5_BurnUSDCOnForB`) | Потеря `1 USDC` при финальной выплате `FOR_B` | **УБИТА** | **УБИТА** | `Inv_Conservation` (`4 424` сген. / `3 768` разл., глубина `14`, `05s`) | [`logs/mutant_5.log`](logs/mutant_5.log) |
| **`mutant_6`** (`M6_R2FallsBackTo5050`) | В раунде 2 разрешён D3/E1 split `50/50` вместо сохранения вердикта R1 | **УБИТА** | **УБИТА** | `Inv_E1Round2NeverSplits5050` (`8 578` сген. / `7 293` разл., глубина `16`, `09s`) | [`logs/mutant_6.log`](logs/mutant_6.log) |

**Ключевой вывод W0.4:** мутационное тестирование доказало свою практическую ценность — исходный инвариант `Inv_NoDeadlineRace` + `Inv_NoSimultaneousEnablement` **пропустил `mutant_1`** (43 944 состояния без ошибки), потому что проверял `ENABLED Submit` вместо реального состояния `submit_time < Deadline`. После добавления явных инвариантов на `submit_time` и `dispute_open_t` (`NoKingV03.tla` стр. 653–657) и повторного прогона `v03_panel5` + всех 6 реплеев все 6 мутаций надёжно перехватываются TLC.

---

## 5. Воспроизведение

```bash
cd verification/v0.3/01_fsm
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v03/panel5 -config v03_panel5.cfg NoKingV03.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v03/atk -config atk_n01_n03_n04_n08.cfg NoKingV03.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v03/base -config v03_base.cfg NoKingV03.tla
for m in 1 2 3 4 5 6; do
  java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -metadir /tmp/tlc_meta_v03/m${m} -config mutant_${m}.cfg NoKingV03_Mutants.tla
done
```
