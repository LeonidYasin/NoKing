--------------------- MODULE NoKingV05_TwoDeals_Mutants ---------------------
EXTENDS NoKingV05_TwoDeals

\* Concurrent G1 mutant: CreateDeal skips capacity reservation (reserved_global stays 0)
M5_CreateDealNoReserve(d) ==
  /\ state[d] = "UNCREATED"
  /\ t_now <= MaxTime - 5
  /\ state' = [state EXCEPT ![d] = "DRAFT"]
  /\ create_t' = [create_t EXCEPT ![d] = t_now]
  /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
  /\ balA' = balA - SellerDeposit
  /\ eSeller' = [eSeller EXCEPT ![d] = SellerDeposit]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               reserved_global, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

StepDealNoRes(d) ==
  \/ M5_CreateDealNoReserve(d)
  \/ Accept(d)
  \/ CancelOrTimeoutDraft(d)
  \/ Start(d)
  \/ TimeoutSeller(d)
  \/ Submit(d)
  \/ CloseReview(d)
  \/ OpenDispute(d)
  \/ PanelFormAndVote(d)
  \/ EscalateDeal(d)
  \/ ResolveR1(d)
  \/ Appeal(d)
  \/ FinalizeOrResolveR2(d)
  \/ TimeoutDispute(d)

NextNoReserve == Tick \/ StepDealNoRes(1) \/ StepDealNoRes(2) \/ TerminalStutter
SpecNoReserve == Init /\ [][NextNoReserve]_vars /\ WF_vars(NextNoReserve)

=============================================================================
