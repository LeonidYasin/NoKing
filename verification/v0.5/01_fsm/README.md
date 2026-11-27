# Y2. Формальные модели TLA+ NoKing v0.5 (`01_fsm`)

## 1. Модели, инструмент и границы

- **Инструмент:** `TLC2 Version 2.19 of 08 August 2024` (`OpenJDK 17.0.21.1`).
- **Модель 1 (1 сделка):** [`NoKingV05.tla`](NoKingV05.tla) — формализует [`exchange-spec-v0.5.md`](../../../protocol/specs/exchange-spec-v0.5.md):
  - **G1:** резервирование ёмкости `cap_reserved = CapReq` и гарантия достаточности `GLOBAL` (`pool_l2_ok = TRUE`) на входе, освобождение резерва во всех терминальных состояниях, невозможность пассивного 50/50 сплита из-за нехватки `GLOBAL` (`Inv_G1NoPassiveExhaustionSplit`);
  - **G2(a–b):** безусловный выбор непересекающегося пула для раунда 2 (`Inv_G2DisjointR2Pool`) + динамический лимит `Amount ≤ Min(V_protocol_max, V_liq_max)` (`Inv_G2DynamicVProtocolMax`);
  - **G3:** потолок награды кипера при авто-подтверждении `REVIEW` (`ProtocolFee = 5, R_keeper_max = 2 → 2` киперу и `3` казне) + исключение сторон `PARTY_A`/`PARTY_B` (`0` награды, `100%` в казну, `Inv_G3KeeperCappedAndPartiesExcluded`);
  - Удержанные свойства **F1, F3** (`Inv_F3TallySealedUntilQuorum` строго как правило FSM), **F5**, **M-09**, нетавтологическая проверка гонок дедлайнов и слабая живость (`Prop_EventuallyTerminal`, `Prop_DisputeAndAppealableExit`).
- **Модель 2 (2 конкурентные сделки с G1):** [`NoKingV05_TwoDeals.tla`](NoKingV05_TwoDeals.tla):
  - `twodeals_v05.cfg`: конкуренция за приём в `CreateDeal` (`CapReq = 35, MaxArbCap = 60, PanelSize = 3, ArbStake = 10, MaxTime = 12`) — сделка №2 не может быть принята, пока сделка №1 не завершится и не освободит резерв;
  - `twodeals_concurrent_v05.cfg`: одновременное исполнение 2 сделок с общей ликвидностью арбитров (`CapReq = 45, MaxArbCap = 100, PanelSize = 2, ArbStake = 10, MaxTime = 10`).
- **Модель мутаций:** [`NoKingV05_Mutants.tla`](NoKingV05_Mutants.tla) + [`NoKingV05_TwoDeals_Mutants.tla`](NoKingV05_TwoDeals_Mutants.tla) — `12` односделочных мутаций (`6` обязательных новых v0.5 + `6` базовых v0.4) + двухсделочный мутант `td_mutant_5_no_reserve`.

### Границы bounded-моделей
- **`v05_panel5.cfg` / `atk_v05` / `replay_1..6`:** `Amount = 100`, `V_protocol_max = 8750`, `V_liq_max = 5000`, `SellerDeposit = 10`, `Penalty = 5`, `ProtocolFee = 5`, `R_keeper_max = 2`, `DisputeDeposit = 5`, `AppealDeposit = 15`, `DelayComp = 5`, `ArbStake = 20`, `ArbPenalty = 5`, `ArbUnrevPenalty = 10`, `BaseArbReward = 2`, `EscBonus = 2`, `KeeperFee = 1`, `PanelSize = 5`, `Q_arb = 3`, `CapReq = 80`, `MaxArbCap = 400`, `T_cancel_grace = 1`, `T_cancel_delay = 1`, `T_accept = 3`, `Deadline = 5`, `T_review = 2`, `T_dispute_max = 3`, `T_appeal = 2`, `MaxTime = 15`, `InitBuyer = 200`, `InitSeller = 200`, `InitArb = 400`, `InitReserve = 50`.
- **`twodeals_v05.cfg`:** `CapReq = 35`, `MaxArbCap = 60`, `PanelSize = 3`, `ArbStake = 10`, `ProtocolFee = 5`, `R_keeper_max = 2`, `T_accept = 1`, `Deadline = 2`, `T_dispute_max = 2`, `T_appeal = 1`, `MaxTime = 12`.

---

## 2. Таблица прогонов TLC (`PROVEN-IN-MODEL` в указанных границах)

| Конфигурация | Сгенерировано сост. | Различных сост. | Глубина | Время | Результат | Лог |
|---|---|---|---|---|---|---|
| [`v05_base.cfg`](v05_base.cfg) (`k=3, Q=2, T_dispute_max=4` с `RedrawPanel`) | `1 775 352` | `1 114 168` | `35` | `11m 09s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v05_base.log`](logs/v05_base.log) |
| [`v05_panel5.cfg`](v05_panel5.cfg) (`k=5, Q=3`, полный набор safety + liveness) | `454 910` | `272 792` | `28` | `06m 56s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/v05_panel5.log`](logs/v05_panel5.log) |
| [`atk_v05.cfg`](atk_v05.cfg) (`N-01, N-03/05, M-01, M-03, M-10, V4-02/06/09`) | `454 910` | `272 792` | `28` | `01m 17s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/atk_v05.log`](logs/atk_v05.log) |
| [`replay_1_double_payout.cfg`](replay_1_double_payout.cfg) (`v0.1 lit_1`) | `454 910` | `272 792` | `28` | `01m 03s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_1_double_payout.log`](logs/replay_1_double_payout.log) |
| [`replay_2_trapped_funds.cfg`](replay_2_trapped_funds.cfg) (`v0.1 lit_2, lit_6`) | `454 910` | `272 792` | `28` | `05m 02s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_2_trapped_funds.log`](logs/replay_2_trapped_funds.log) |
| [`replay_3_burned_usdc.cfg`](replay_3_burned_usdc.cfg) (`v0.1 lit_3`) | `454 910` | `272 792` | `28` | `32s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_3_burned_usdc.log`](logs/replay_3_burned_usdc.log) |
| [`replay_4_zero_vote.cfg`](replay_4_zero_vote.cfg) (`v0.1 lit_4`) | `454 910` | `272 792` | `28` | `27s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_4_zero_vote.log`](logs/replay_4_zero_vote.log) |
| [`replay_5_deadline_race.cfg`](replay_5_deadline_race.cfg) (`v0.1 lit_5`) | `454 910` | `272 792` | `28` | `01m 06s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_5_deadline_race.log`](logs/replay_5_deadline_race.log) |
| [`replay_6_local_empty.cfg`](replay_6_local_empty.cfg) (`L0=L1=FALSE`, `G1 => L2=TRUE`) | `113 690` | `68 198` | `28` | `28s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/replay_6_local_empty.log`](logs/replay_6_local_empty.log) |
| [`twodeals_v05.cfg`](twodeals_v05.cfg) (2 сделки, G1 блокировка по ёмкости) | `756 203` | `491 115` | `39` | `05m 09s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/twodeals_v05.log`](logs/twodeals_v05.log) |
| [`twodeals_concurrent_v05.cfg`](twodeals_concurrent_v05.cfg) (2 сделки параллельно) | `416 568` | `217 559` | `34` | `03m 44s` | **0 ошибок (`PROVEN-IN-MODEL`)** | [`logs/twodeals_concurrent_v05.log`](logs/twodeals_concurrent_v05.log) |

*(Нетривиальность по `-coverage 1`: в `v05_base.log` `RedrawPanel` сработал `30 336:30 336`, `EscalateLevel` — `2 616:5 976`, `TimeoutR1Split5050` — `2 856:2 856`, `Appeal` — `7 488:17 280`; в `v05_panel5.log` антецедент `Inv_G1NoPassiveExhaustionSplit` и `Inv_F1SplitOnlyAfterChain` сработал `1 410` раз, `Inv_G1CapacityReservedNonTerminal` — `249 550`, `Inv_G1CapacityReleasedTerminal` — `23 242`, `Inv_G2DisjointR2Pool` — `123 600`, `Inv_G3KeeperCappedAndPartiesExcluded` — `80`, `Inv_F3TallySealedUntilQuorum` — `114 750`, `Inv_F5DefaultOnlyOnSellerTimeout` — `8 / 272 760 / 16`.)*

*(Примечание: при разработке `NoKingV05_TwoDeals` первый прогон TLC поймал реальный краевой случай общего таймера `T_dispute_max` при просрочке на L0 — он задокументирован как `V5-02` в [`05_new_issues.md`](../05_new_issues.md).)*

---

## 3. Мутационное тестирование (`13/13` мутантов убиты)

| # | Мутация | Внесённое нарушение | Пойманный инвариант / свойство | Состояния (сген. / разл.) | Время | Лог |
|---|---|---|---|---|---|---|
| `mutant_1` | `M1_InitNoCapCheck` *(нов. G1)* | Убрана проверка ёмкости `GLOBAL` в `e_create` (`pool_l2_ok = FALSE`) | `Inv_G1NoPassiveExhaustionSplit` | `4 696 / 3 694` | `10s` | [`logs/mutant_1.log`](logs/mutant_1.log) |
| `mutant_2` | `M2_AppealSamePool` *(нов. G2)* | Раунд 2 разрешён в том же пуле `r1_pool` (`V4-09`) | `Inv_G2DisjointR2Pool` | `4 805 / 3 903` | `13s` | [`logs/mutant_2.log`](logs/mutant_2.log) |
| `mutant_3` | `M3_TimeoutReviewUncapped` *(нов. G3)* | Снят потолок `R_keeper_max` (платит `5 > 2`) | `Inv_G3KeeperCappedAndPartiesExcluded` | `437 / 360` | `07s` | [`logs/mutant_3.log`](logs/mutant_3.log) |
| `mutant_4` | `M4_TimeoutReviewPartyPaid` *(нов. G3)* | Разрешена выплата кипер-награды стороне `PARTY_A` | `Inv_G3KeeperCappedAndPartiesExcluded` | `434 / 356` | `07s` | [`logs/mutant_4.log`](logs/mutant_4.log) |
| `mutant_5` | `M5_InitNoReserve` *(нов. G1)* | Не резервирует ёмкость при приёме (`cap_reserved = 0`) | `Inv_G1CapacityReservedNonTerminal` | `Init` (`0`) | `06s` | [`logs/mutant_5.log`](logs/mutant_5.log) |
| `td_mutant_5` | `M5_CreateDealNoReserve` *(2 сделки)* | В `NoKingV05_TwoDeals` `CreateDeal` не инкрементирует `reserved_global` | `Inv_TwoDealG1CapacityBound` | `2 / 2` | `02s` | [`logs/td_mutant_5_no_reserve.log`](logs/td_mutant_5_no_reserve.log) |
| `mutant_6` | `M6_PassiveSplitDirect` *(нов. F1/G1)* | Разрешён пассивный сплит на `esc_level = 0` без эскалации | `Inv_F1SplitOnlyAfterChain` | `268 / 224` | `06s` | [`logs/mutant_6.log`](logs/mutant_6.log) |
| `mutant_7` | `M7_R2TimeoutSplit5050` | Таймаут R2 возвращает 50/50 сплит | `Inv_F1SplitOnlyAfterChain` | `27 533 / 23 123` | `21s` | [`logs/mutant_7.log`](logs/mutant_7.log) |
| `mutant_8` | `M8_LeakTallyRedraw` *(k=3, T=4)* | `RedrawPanel` снимает `tally_sealed` до `Q_arb` | `Inv_F3TallySealedUntilQuorum` | `3 233 / 2 530` | `05s` | [`logs/mutant_8.log`](logs/mutant_8.log) |
| `mutant_9` | `M9_InitNoDynamicCap` (`Amount=6000`) | Обход динамического `V_liq_max = 5000` | `Inv_G2DynamicVProtocolMax` | `Init` (`0`) | `02s` | [`logs/mutant_9.log`](logs/mutant_9.log) |
| `mutant_10` | `M10_DefaultOnReviewTimeout` | Таймаут `REVIEW` инкрементирует `deadline_defaults` | `Inv_F5DefaultOnlyOnSellerTimeout` | `442 / 362` | `03s` | [`logs/mutant_10.log`](logs/mutant_10.log) |
| `mutant_11` | `M11_ZeroVoteBug` | Возвращён баг победы при 0 голосов | `Inv_NoZeroVoteWin` | `3 159 / 2 503` | `05s` | [`logs/mutant_11.log`](logs/mutant_11.log) |
| `mutant_12` | `M12_DropTimeoutsDeadlock` *(k=3, T=4)* | Удалены таймауты разрешения споров | `Deadlock reached` | `3 717 / 2 927` | `07s` | [`logs/mutant_12.log`](logs/mutant_12.log) |

---

## 4. Воспроизведение

```bash
cd verification/v0.5/01_fsm
mkdir -p /tmp/tlc_meta_v05
for c in v05_panel5 atk_v05 replay_1_double_payout replay_2_trapped_funds replay_3_burned_usdc replay_4_zero_vote replay_5_deadline_race; do
  java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/${c} -config ${c}.cfg NoKingV05.tla
done
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/r6 -config replay_6_local_empty.cfg NoKingV05_Mutants.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/td -config twodeals_v05.cfg NoKingV05_TwoDeals.tla
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/tdc -config twodeals_concurrent_v05.cfg NoKingV05_TwoDeals.tla
for m in $(seq 1 12); do
  java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/m${m} -config mutant_${m}.cfg NoKingV05_Mutants.tla
done
java -cp /tmp/tla2tools.jar tlc2.TLC -workers auto -coverage 1 -metadir /tmp/tlc_meta_v05/tdm5 -config td_mutant_5_no_reserve.cfg NoKingV05_TwoDeals_Mutants.tla
```
