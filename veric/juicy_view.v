From iris.algebra Require Export gmap agree.
From iris.algebra Require Import local_updates proofmode_classes big_op.
From VST.zlist Require Import sublist.
From VST.msl Require Import shares.
From VST.veric Require Export base Memory share_alg dfrac view shared.
From iris_ora.algebra Require Export ora gmap agree.
From iris.prelude Require Import options.

(* We can't import compcert.lib.Maps because their lookup notations conflict with stdpp's.
   We can define lookup instances, which require one more ! apiece than CompCert's notation. *)
Global Instance ptree_lookup A : Lookup positive A (Maps.PTree.t A) := Maps.PTree.get(A := A).
Global Instance pmap_lookup A : LookupTotal positive A (Maps.PMap.t A) := Maps.PMap.get(A := A).

Lemma perm_order''_refl : forall s, Mem.perm_order'' s s.
Proof.
  destruct s; simpl; try done.
  apply perm_refl.
Qed.

Lemma perm_order''_trans: forall a b c, Mem.perm_order'' a b ->  Mem.perm_order'' b c ->
                             Mem.perm_order'' a c.
Proof.
   intros a b c H1 H2; destruct a, b, c; inversion H1; inversion H2; subst; eauto;
           eapply perm_order_trans; eauto.
Qed.

Lemma perm_order''_None : forall a, Mem.perm_order'' a None.
Proof. destruct a; simpl; auto. Qed.

Definition perm_of_sh (sh: Share.t): option permission :=
  if writable0_share_dec sh
  then if eq_dec sh Share.top
          then Some Freeable
          else Some Writable
  else if readable_share_dec sh
       then Some Readable
       else if eq_dec sh Share.bot
                 then None
            else Some Nonempty.
Functional Scheme perm_of_sh_ind := Induction for perm_of_sh Sort Prop.

Definition perm_of_dfrac dq :=
  match dq with
  | DfracOwn sh => perm_of_sh sh
  | DfracDiscarded => Some Readable
  | DfracBoth sh => if Mem.perm_order'_dec (perm_of_sh sh) Readable then perm_of_sh sh else Some Readable
  end.

Definition perm_of_res' {V} (r: option (dfrac * V)) :=
  match r with
  | Some (dq, _) => perm_of_dfrac dq
  | None => None
  end.

Lemma perm_of_sh_mono : forall (sh1 sh2 : shareR), sh1 ⋅ sh2 ≠ Share.bot -> Mem.perm_order'' (perm_of_sh (sh1 ⋅ sh2)) (perm_of_sh sh1).
Proof.
  intros ?? H.
  pose proof (proj1 (share_op_equiv sh1 sh2 _) eq_refl) as J.
  rewrite -> if_false in J by auto; destruct J as (? & ? & J).
  unfold perm_of_sh.
  destruct (writable0_share_dec sh1).
  { eapply join_writable01 in w; eauto.
    rewrite -> if_true by auto.
    if_tac; if_tac; simpl; try constructor.
    subst; rewrite -> (@only_bot_joins_top sh2) in H1 by (eexists; eauto); contradiction. }
  if_tac; [repeat if_tac; constructor|].
  destruct (readable_share_dec sh1).
  { eapply join_readable1 in r; eauto.
    rewrite (if_true _ _ _ _ _ r); constructor. }
  repeat if_tac; try constructor; contradiction.
Qed.

Lemma perm_order_antisym : forall p1 p2, ~perm_order p1 p2 -> perm_order p2 p1.
Proof.
  destruct p1, p2; try constructor; intros X; contradiction X; constructor.
Qed.

Lemma perm_order'_antisym : forall p1 p2, ~Mem.perm_order' p1 p2 -> Mem.perm_order'' (Some p2) p1.
Proof.
  destruct p1; simpl; auto; apply perm_order_antisym.
Qed.

Lemma perm_of_dfrac_mono : forall d1 d2, ✓d2 -> d1 ≼ d2 -> Mem.perm_order'' (perm_of_dfrac d2) (perm_of_dfrac d1).
Proof.
  intros ?? Hv [d0 ->%leibniz_equiv].
  destruct d1, d0; simpl in *; repeat if_tac; auto; try (apply perm_order''_refl || (by apply perm_of_sh_mono) || (by destruct Hv; apply perm_of_sh_mono) || constructor).
  - by apply perm_order'_antisym.
  - destruct Hv; eapply perm_order''_trans, perm_of_sh_mono; [apply perm_order'_antisym|]; eauto.
  - destruct Hv; eapply perm_order''_trans, perm_of_sh_mono; [apply perm_order'_antisym|]; eauto.
  - destruct Hv; eapply perm_order''_trans, perm_of_sh_mono; [apply perm_order'_antisym|]; eauto.
Qed.

Class resource_ops (V : ofe) := {
  perm_of_res : option (dfrac * V) -> option permission;
  memval_of : dfrac * V -> option memval;
  perm_of_res_None : perm_of_res None = None;
  perm_of_res_mono : forall d1 d2 (r : V), ✓d2 -> d1 ≼ d2 -> Mem.perm_order'' (perm_of_res (Some (d2, r))) (perm_of_res (Some (d1, r)));
  perm_of_res_ne : forall n d (r1 r2 : V), r1 ≡{n}≡ r2 -> perm_of_res (Some (d, r1)) = perm_of_res (Some (d, r2));
  perm_of_res_max : forall r, Mem.perm_order'' (perm_of_res' r) (perm_of_res r);
  memval_of_mono : forall d1 d2 (r : V) v, memval_of (d1, r) = Some v -> d1 ≼ d2 -> memval_of (d2, r) = Some v;
  memval_of_ne : forall n d (r1 r2 : V) v, memval_of (d, r1) = Some v -> r1 ≡{n}≡ r2 -> memval_of (d, r2) = Some v
}.

(** * ORA for a juicy mem. An algebra where a resource map is a view of a CompCert memory if it is
      coherent with that memory. *)

Local Definition juicy_view_fragUR (V : ofe) : uora :=
  gmapUR address (sharedR V).

(** View relation. *)
Section rel.
  Context (V : ofe) {ResOps : resource_ops V}.
  Implicit Types (m : Memory.mem) (k : address) (r : option (dfrac * V)) (v : memval) (n : nat).
  Implicit Types (f : gmap address (dfrac * agree V)).

  Notation rmap := (gmap address (dfrac * agree V)).

  Definition elem_of_agree {A} (x : agree A) : { a | a ∈ agree_car x}.
  Proof. destruct x as [[|a ?] ?]; [done | exists a; apply elem_of_cons; auto]. Qed.

  Lemma elem_of_agree_ne : forall {A} n (x y : agreeR A), ✓{n} x -> x ≡{n}≡ y -> proj1_sig (elem_of_agree x) ≡{n}≡ proj1_sig (elem_of_agree y).
  Proof.
    intros; destruct (elem_of_agree x), (elem_of_agree y); simpl.
    destruct (proj1 H0 _ e) as (? & Hv2 & ->).
    rewrite H0 in H; eapply agree_validN_def; done.
  Qed.

  Definition resR_to_resource : optionR (prodR dfracR (agreeR V)) -> option (dfrac * V) :=
    option_map (fun '(q, a) => (q, proj1_sig (elem_of_agree a))).

  Definition resource_at f k := resR_to_resource (f !! k).
  Local Infix "@" := resource_at (at level 50, no associativity).

  Definition contents_at (m: mem) (loc: address) : memval :=
    Maps.ZMap.get (snd loc) (Maps.PMap.get (fst loc) (Mem.mem_contents m)).

  Definition contents_cohere (m: mem) k r :=
    forall v, r ≫= memval_of = Some v -> contents_at m k = v.

  Definition access_cohere (m: mem) k r :=
    Mem.perm_order'' (access_at m k Cur) (perm_of_res r).

  Definition max_access_at m loc := access_at m loc Max.

  Definition max_access_cohere (m: mem) k r :=
    Mem.perm_order'' (max_access_at m k) (perm_of_res' r).

  Definition alloc_cohere (m: mem) k r :=
    (fst k >= Mem.nextblock m)%positive -> r = None.

  Definition coherent_loc (m: mem) k r := contents_cohere m k r ∧ access_cohere m k r ∧ max_access_cohere m k r ∧ alloc_cohere m k r.

  Definition coherent n (m : leibnizO mem) phi := ✓{n} phi ∧ forall loc, coherent_loc m loc (phi @ loc).

  Local Lemma coherent_mono n1 n2 (m1 m2 : leibnizO mem) f1 f2 :
    coherent n1 m1 f1 →
    m1 ≡{n2}≡ m2 →
    f2 ≼{n2} f1 →
    n2 ≤ n1 →
    coherent n2 m2 f2.
  Proof using Type*.
    intros (Hv & H) -> Hf Hn.
    assert (✓{n2} f2) as Hv2.
    { eapply cmra_validN_includedN; eauto.
      eapply cmra_validN_le; eauto. }
    split; first done.
    intros loc; specialize (Hv loc); specialize (Hv2 loc); specialize (H loc).
    rewrite lookup_includedN in Hf; specialize (Hf loc); rewrite option_includedN in Hf.
    destruct H as (Hcontents & Hcur & Hmax & Halloc); unfold resource_at in *; repeat split.
    - unfold contents_cohere in *; intros.
      apply Hcontents.
      destruct Hf as [Hf | ((d2, v2) & (d1, v1) & Hf2 & Hf1 & Hf)]; [rewrite Hf in H; inv H|].
      rewrite Hf2 in H Hv2; inv H.
      rewrite Hf1 /= in Hv |- *.
      rewrite pair_includedN in Hf.
      destruct Hv as [_ Hv], Hv2 as [_ Hv2].
      eapply cmra_validN_le in Hv; eauto.
      assert (v2 ≡{n2}≡ v1) as Hvs by (by destruct Hf as [[_ ?] | [_ ?%agree_valid_includedN]]).
      rewrite H1; eapply memval_of_ne, elem_of_agree_ne, Hvs; auto.
      destruct Hf as [[Hd _] | [Hd _]]; [by rewrite -discrete_iff /= in Hd; apply leibniz_equiv in Hd; subst|].
      eapply memval_of_mono; eauto.
    - unfold access_cohere in *.
      destruct Hf as [Hf | ((?, v2) & (?, v1) & Hf2 & Hf1 & Hf)]; [rewrite Hf perm_of_res_None; apply perm_order''_None|].
      eapply perm_order''_trans; [apply Hcur|].
      rewrite Hf1 Hf2 /= in Hv Hv2 |- *.
      rewrite pair_includedN in Hf.
      destruct Hv as [? Hv], Hv2 as [_ Hv2].
      eapply cmra_validN_le in Hv; eauto.
      assert (v2 ≡{n2}≡ v1) as Hvs by (by destruct Hf as [[_ ?] | [_ ?%agree_valid_includedN]]).
      erewrite <- perm_of_res_ne by (apply elem_of_agree_ne, Hvs; auto).
      destruct Hf as [[Hd _] | [Hd _]]; [by rewrite -discrete_iff /= in Hd; apply leibniz_equiv in Hd; subst; apply perm_order''_refl|].
      apply perm_of_res_mono; auto.
    - unfold max_access_cohere in *.
      destruct Hf as [Hf | ((?, v2) & (?, v1) & Hf2 & Hf1 & Hf)]; [rewrite Hf; apply perm_order''_None|].
      eapply perm_order''_trans; [apply Hmax|].
      rewrite Hf1 Hf2 /= in Hv Hv2 |- *.
      rewrite pair_includedN in Hf.
      destruct Hf as [[Hd _] | [Hd _]]; [by rewrite -discrete_iff /= in Hd; apply leibniz_equiv in Hd; subst; apply perm_order''_refl|].
      destruct Hv; apply perm_of_dfrac_mono; auto.
    - unfold alloc_cohere in *; intros H; specialize (Halloc H).
      destruct Hf as [Hf | (? & ? & Hf2 & Hf1 & _)]; [by rewrite Hf|].
      rewrite Hf1 in Halloc; discriminate.
  Qed.

  Local Lemma coherent_valid n m f :
    coherent n m f → ✓{n} f.
  Proof.
    intros H; apply H.
  Qed.

  Lemma coherent_None m k : coherent_loc m k None.
  Proof.
    repeat split.
    - by intros ?.
    - rewrite /access_cohere perm_of_res_None; apply perm_order''_None.
    - apply perm_order''_None.
  Qed.

  Local Lemma coherent_unit n :
    ∃ m, coherent n m ε.
  Proof using Type*.
    exists Mem.empty; repeat split; rewrite /resource_at lookup_empty; apply coherent_None.
  Qed.

  Local Canonical Structure coherent_rel : view_rel (leibnizO mem) (juicy_view_fragUR V) :=
    ViewRel coherent coherent_mono coherent_valid coherent_unit.

  Definition access_of_rmap f b ofs (k : perm_kind) :=
    match k with
    | Max => perm_of_res' (f @ (b, ofs))
    | Cur => perm_of_res (f @ (b, ofs))
    end.

  Definition make_access (next : Values.block) (r : rmap) :=
    fold_right (fun b p => Maps.PTree.set b (access_of_rmap r b) p) (Maps.PTree.empty _)
    (map Z.to_pos (tl (upto (Pos.to_nat next)))).

  Lemma make_access_get_aux : forall l f b t,
    Maps.PTree.get b (fold_right (fun b p => Maps.PTree.set b (access_of_rmap f b) p) t l) =
    if In_dec eq_block b l then Some (access_of_rmap f b) else Maps.PTree.get b t.
  Proof.
    induction l; simpl; auto; intros.
    destruct (eq_block a b).
    - subst; apply Maps.PTree.gss.
    - rewrite Maps.PTree.gso; last auto.
      rewrite IHl.
      if_tac; auto.
  Qed.

  Lemma make_access_get : forall next f b,
    Maps.PTree.get b (make_access next f) =
    if Pos.ltb b next then Some (access_of_rmap f b) else None.
  Proof.
    intros; unfold make_access.
    rewrite make_access_get_aux.
    if_tac; destruct (Pos.ltb_spec0 b next); auto.
    - rewrite in_map_iff in H; destruct H as (? & ? & Hin); subst.
      destruct (Pos.to_nat next) eqn: Hnext.
      { pose proof (Pos2Nat.is_pos next); lia. }
      simpl in Hin.
      rewrite in_map_iff in Hin; destruct Hin as (? & ? & Hin); subst.
      apply In_upto in Hin.
      destruct x0; simpl in *; lia.
    - contradiction H.
      rewrite in_map_iff; do 2 eexists.
      { apply Pos2Z.id. }
      destruct (Pos.to_nat next) eqn: Hnext.
      { pose proof (Pos2Nat.is_pos next); lia. }
      simpl.
      rewrite in_map_iff; do 2 eexists.
      { rewrite -> Zminus_succ_l.
        unfold Z.succ. rewrite -> Z.add_simpl_r; reflexivity. }
      rewrite In_upto; lia.
  Qed.

  Definition make_contents (r : rmap) : Maps.PMap.t (Maps.ZMap.t memval) :=
    map_fold (fun '(b, ofs) '(d, v) c => Maps.PMap.set b (Maps.ZMap.set ofs
      (match memval_of (d, proj1_sig (elem_of_agree v)) with Some v => v | None => Undef end) (c !!! b)) c)
      (Maps.PMap.init (Maps.ZMap.init Undef)) r.

  Lemma make_contents_get : forall f (b : Values.block) ofs,
    Maps.ZMap.get ofs ((make_contents f) !!! b) = match f @ (b, ofs) ≫= memval_of with Some v => v | _ => Undef end.
  Proof.
    intros; unfold make_contents.
    apply (map_fold_ind (fun c f => Maps.ZMap.get ofs (c !!! b) = match f @ (b, ofs) ≫= memval_of with Some v => v | _ => Undef end)).
    - rewrite /lookup_total /pmap_lookup Maps.PMap.gi Maps.ZMap.gi /resource_at lookup_empty //.
    - intros (b1, ofs1) (d, v) ?? Hi H.
      destruct (eq_dec b1 b).
      + subst; rewrite /lookup_total /pmap_lookup Maps.PMap.gss.
        destruct (eq_dec ofs1 ofs).
        * subst; rewrite Maps.ZMap.gss /resource_at lookup_insert //.
        * rewrite Maps.ZMap.gso; last done.
          rewrite /resource_at lookup_insert_ne //.
          congruence.
      + rewrite /lookup_total /pmap_lookup Maps.PMap.gso; last done.
        rewrite /resource_at lookup_insert_ne //.
        congruence.
  Qed.

  Lemma make_contents_default : forall f (b : Values.block), (make_contents f !!! b).1 = Undef.
  Proof.
    intros; unfold make_contents.
    apply (map_fold_ind (fun c f => (c !!! b).1 = Undef)); try done.
    intros (b1, ofs) (?, ?) ????.
    destruct (eq_dec b1 b).
    - subst; rewrite /lookup_total /pmap_lookup Maps.PMap.gss //.
    - rewrite /lookup_total /pmap_lookup Maps.PMap.gso //.
  Qed.

  Definition maxblock_of_rmap f := map_fold (fun '(b, _) _ c => Pos.max b c) 1%positive f.

  Lemma maxblock_max : forall f b ofs, (b > maxblock_of_rmap f)%positive -> f !! (b, ofs) = None.
  Proof.
    intros ???; unfold maxblock_of_rmap.
    apply (map_fold_ind (fun c f => (b > c)%positive -> f !! (b, ofs) = None)).
    - by rewrite lookup_empty.
    - intros (b1, ?) (?, ?) ??? IH ?.
      destruct (eq_dec b1 b); first lia.
      rewrite lookup_insert_ne; last congruence.
      apply IH; lia.
  Qed.

  Program Definition mem_of_rmap f : mem :=
    {| Mem.mem_contents := make_contents f;
       Mem.mem_access := (fun _ _ => None, make_access (maxblock_of_rmap f + 1)%positive f);
       Mem.nextblock := (maxblock_of_rmap f + 1)%positive |}.
  Next Obligation.
  Proof.
    intros; rewrite /Maps.PMap.get make_access_get.
    simple_if_tac; last done.
    apply perm_of_res_max.
  Qed.
  Next Obligation.
  Proof.
    intros.
    rewrite /Maps.PMap.get make_access_get.
    destruct (Pos.ltb_spec b (maxblock_of_rmap f + 1)%positive); done.
  Qed.
  Next Obligation.
  Proof.
    apply make_contents_default.
  Qed.

  Lemma mem_of_rmap_coherent : forall n f, ✓{n} f -> coherent n (mem_of_rmap f) f.
  Proof.
    intros; split; first done.
    intros (b, ofs); simpl.
    repeat split.
    - rewrite /contents_cohere /contents_at /= => ? Hv.
      rewrite make_contents_get Hv //.
    - rewrite /access_cohere /access_at /=.
      rewrite /Maps.PMap.get make_access_get.
      destruct (Pos.ltb_spec b (maxblock_of_rmap f + 1)%positive).
      + apply perm_order''_refl.
      + simpl. rewrite /resource_at maxblock_max; last lia.
        rewrite perm_of_res_None //.
    - rewrite /max_access_cohere /max_access_at /access_at /=.
      rewrite /Maps.PMap.get make_access_get.
      destruct (Pos.ltb_spec b (maxblock_of_rmap f + 1)%positive).
      + apply perm_order''_refl.
      + simpl. rewrite /resource_at maxblock_max //; lia.
    - rewrite /alloc_cohere /= => ?.
      rewrite /resource_at maxblock_max //; lia.
  Qed.

  Local Lemma coherent_rel_exists n f :
    (∃ m, coherent_rel n m f) ↔ ✓{n} f.
  Proof.
    split.
    - intros [m Hrel]. eapply coherent_valid, Hrel.
    - intros; eexists; apply mem_of_rmap_coherent; auto.
  Qed.

  Local Lemma coherent_rel_unit n m : coherent_rel n m ε.
  Proof.
    split. { apply uora_unit_validN. }
    simpl; intros; rewrite /resource_at lookup_empty /=.
    apply coherent_None.
  Qed.

  Local Lemma coherent_rel_discrete :
    OfeDiscrete V → ViewRelDiscrete coherent_rel.
  Proof.
    intros ? n m f [Hv Hrel].
    split; last done.
    by apply cmra_discrete_valid_iff_0.
  Qed.

  Lemma rmap_orderN_includedN : ∀n f1 f2, ✓{n} f2 -> f1 ≼ₒ{n} f2 -> f1 ≼{n} f2.
  Proof.
    intros ??? Hv; rewrite lookup_includedN; intros.
    specialize (H i); specialize (Hv i).
    destruct (f1 !! i) as [(d1, v1)|] eqn: Hf1, (f2 !! i) as [(d2, v2)|] eqn: Hf2; rewrite ?Hf1 Hf2 /= in H Hv |- *; try done.
    - rewrite Some_includedN pair_includedN; destruct Hv, H as [Hd Hv]; simpl in *.
      apply agree_order_dist in Hv as ->; last done.
      destruct Hd; subst; auto.
      right; split; auto; eexists; eauto.
    - rewrite option_includedN; auto.
  Qed.

  Local Lemma coherent_rel_order : ∀n a x y, x ≼ₒ{n} y → coherent_rel n a y → coherent_rel n a x.
  Proof.
    intros ???? Hord [? Hy].
    eapply coherent_mono; first (by split); auto.
    apply rmap_orderN_includedN; auto.
  Qed.

End rel.

Arguments resource_at {_} _ _.
Arguments coherent_loc {_} {_} _ _ _.

Local Existing Instance coherent_rel_discrete.

(** [juicy_view] is a notation to give canonical structure search the chance
to infer the right instances (see [auth]). *)
Notation juicy_view V := (view (@coherent _ _ V)).
Definition juicy_viewO (V : ofe) `{resource_ops V} : ofe := viewO (coherent_rel V).
Definition juicy_viewC (V : ofe) `{resource_ops V} : cmra := viewC (coherent_rel V).
Definition juicy_viewUC (V : ofe) `{resource_ops V} : ucmra := viewUC (coherent_rel V).
Canonical Structure juicy_viewR (V : ofe) `{resource_ops V} : ora := view.viewR (coherent_rel V) (coherent_rel_order V).
Canonical Structure juicy_viewUR (V : ofe) `{resource_ops V} : uora := viewUR (coherent_rel V).

Section definitions.
  Context {V : ofe} {ResOps : resource_ops V}.

  Definition juicy_view_auth (dq : dfrac) (m : leibnizO mem) : juicy_viewUR V :=
    ●V{dq} m.
  Definition juicy_view_frag (k : address) (dq : dfrac) (v : V) : juicy_viewUR V :=
    ◯V {[k := (dq, to_agree v)]}.
End definitions.

Section lemmas.
  Context {V : ofe} {ResOps : resource_ops V}.
  Implicit Types (m : mem) (q : shareR) (dq : dfrac) (v : V).

  Global Instance : Params (@juicy_view_auth) 3 := {}.
  Global Instance juicy_view_auth_ne dq : NonExpansive (juicy_view_auth (V:=V) dq).
  Proof. solve_proper. Qed.
  Global Instance juicy_view_auth_proper dq : Proper ((≡) ==> (≡)) (juicy_view_auth (V:=V) dq).
  Proof. apply ne_proper, _. Qed.

  Global Instance : Params (@juicy_view_frag) 4 := {}.
  Global Instance juicy_view_frag_ne k oq : NonExpansive (juicy_view_frag (V:=V) k oq).
  Proof. solve_proper. Qed.
  Global Instance juicy_view_frag_proper k oq : Proper ((≡) ==> (≡)) (juicy_view_frag (V:=V) k oq).
  Proof. apply ne_proper, _. Qed.

  (* Helper lemmas *)
  Lemma elem_of_to_agree : forall {A} (v : A), proj1_sig (elem_of_agree (to_agree v)) = v.
  Proof.
    intros; destruct (elem_of_agree (to_agree v)); simpl.
    rewrite -elem_of_list_singleton //.
  Qed.

  Local Lemma coherent_rel_lookup n m k dq v :
    coherent_rel V n m {[k := (dq, to_agree v)]} ↔ ✓ dq ∧ coherent_loc m k (Some (dq, v)).
  Proof.
    split.
    - intros [Hv Hloc].
      specialize (Hv k); specialize (Hloc k).
      rewrite /resource_at lookup_singleton /= in Hv Hloc.
      rewrite elem_of_to_agree in Hloc; destruct Hv; auto.
    - intros [Hv Hloc]; split.
      + intros i; destruct (decide (k = i)).
        * subst; rewrite lookup_singleton //.
        * rewrite lookup_singleton_ne //.
      + intros i; rewrite /resource_at; destruct (decide (k = i)).
        * subst; rewrite lookup_singleton /= elem_of_to_agree //.
        * rewrite lookup_singleton_ne // /=; apply coherent_None.
  Qed.

  (** Composition and validity *)
  Lemma juicy_view_auth_dfrac_op dp dq m :
    juicy_view_auth (dp ⋅ dq) m ≡
    juicy_view_auth dp m ⋅ juicy_view_auth dq m.
  Proof. by rewrite /juicy_view_auth view_auth_dfrac_op. Qed.
  Global Instance juicy_view_auth_dfrac_is_op dq dq1 dq2 m :
    IsOp dq dq1 dq2 → IsOp' (juicy_view_auth dq m) (juicy_view_auth dq1 m) (juicy_view_auth dq2 m).
  Proof. rewrite /juicy_view_auth. apply _. Qed.

  Lemma juicy_view_auth_dfrac_op_invN n dp m1 dq m2 :
    ✓{n} (juicy_view_auth dp m1 ⋅ juicy_view_auth dq m2) → m1 = m2.
  Proof. by intros ?%view_auth_dfrac_op_invN. Qed.
  Lemma juicy_view_auth_dfrac_op_inv dp m1 dq m2 :
    ✓ (juicy_view_auth dp m1 ⋅ juicy_view_auth dq m2) → m1 = m2.
  Proof. by intros ?%view_auth_dfrac_op_inv. Qed.

  Lemma juicy_view_auth_dfrac_validN m n dq : ✓{n} juicy_view_auth dq m ↔ ✓ dq.
  Proof.
    rewrite view_auth_dfrac_validN. intuition. apply coherent_rel_unit.
  Qed.
  Lemma juicy_view_auth_dfrac_valid m dq : ✓ juicy_view_auth dq m ↔ ✓ dq.
  Proof.
    rewrite view_auth_dfrac_valid. intuition. apply coherent_rel_unit.
  Qed.
  Lemma juicy_view_auth_valid m : ✓ juicy_view_auth (DfracOwn Tsh) m.
  Proof. rewrite juicy_view_auth_dfrac_valid. done. Qed.

  Lemma juicy_view_auth_dfrac_op_validN n dq1 dq2 m1 m2 :
    ✓{n} (juicy_view_auth dq1 m1 ⋅ juicy_view_auth dq2 m2) ↔ ✓ (dq1 ⋅ dq2) ∧ m1 = m2.
  Proof.
    rewrite view_auth_dfrac_op_validN. intuition. apply coherent_rel_unit.
  Qed.
  Lemma juicy_view_auth_dfrac_op_valid dq1 dq2 m1 m2 :
    ✓ (juicy_view_auth dq1 m1 ⋅ juicy_view_auth dq2 m2) ↔ ✓ (dq1 ⋅ dq2) ∧ m1 = m2.
  Proof.
    rewrite view_auth_dfrac_op_valid. intuition. apply coherent_rel_unit.
  Qed.

  Lemma juicy_view_auth_op_validN n m1 m2 :
    ✓{n} (juicy_view_auth (DfracOwn Tsh) m1 ⋅ juicy_view_auth (DfracOwn Tsh) m2) ↔ False.
  Proof. apply view_auth_op_validN. Qed.
  Lemma juicy_view_auth_op_valid m1 m2 :
    ✓ (juicy_view_auth (DfracOwn Tsh) m1 ⋅ juicy_view_auth (DfracOwn Tsh) m2) ↔ False.
  Proof. apply view_auth_op_valid. Qed.

  Lemma juicy_view_frag_validN n k dq v : ✓{n} juicy_view_frag k dq v ↔ ✓ dq.
  Proof.
    rewrite view_frag_validN coherent_rel_exists singleton_validN pair_validN.
    naive_solver.
  Qed.
  Lemma juicy_view_frag_valid k dq v : ✓ juicy_view_frag k dq v ↔ ✓ dq.
  Proof.
    rewrite cmra_valid_validN. setoid_rewrite juicy_view_frag_validN.
    naive_solver eauto using O.
  Qed.

  Lemma juicy_view_frag_op k dq1 dq2 v :
    juicy_view_frag k (dq1 ⋅ dq2) v ≡ juicy_view_frag k dq1 v ⋅ juicy_view_frag k dq2 v.
  Proof. rewrite -view_frag_op singleton_op -cmra.pair_op agree_idemp //. Qed.
  Lemma juicy_view_frag_add k q1 q2 v :
    juicy_view_frag k (DfracOwn (q1 ⋅ q2)) v ≡
      juicy_view_frag k (DfracOwn q1) v ⋅ juicy_view_frag k (DfracOwn q2) v.
  Proof. rewrite -juicy_view_frag_op. done. Qed.

  Lemma juicy_view_frag_op_validN n k dq1 dq2 v1 v2 :
    ✓{n} (juicy_view_frag k dq1 v1 ⋅ juicy_view_frag k dq2 v2) ↔
      ✓ (dq1 ⋅ dq2) ∧ v1 ≡{n}≡ v2.
  Proof.
    rewrite view_frag_validN coherent_rel_exists singleton_op singleton_validN.
    by rewrite -cmra.pair_op pair_validN to_agree_op_validN.
  Qed.
  Lemma juicy_view_frag_op_valid k dq1 dq2 v1 v2 :
    ✓ (juicy_view_frag k dq1 v1 ⋅ juicy_view_frag k dq2 v2) ↔ ✓ (dq1 ⋅ dq2) ∧ v1 ≡ v2.
  Proof.
    rewrite view_frag_valid. setoid_rewrite coherent_rel_exists.
    rewrite -cmra_valid_validN singleton_op singleton_valid.
    by rewrite -cmra.pair_op pair_valid to_agree_op_valid.
  Qed.
  (* FIXME: Having a [valid_L] lemma is not consistent with [auth] and [view]; they
     have [inv_L] lemmas instead that just have an equality on the RHS. *)
  Lemma juicy_view_frag_op_valid_L `{!LeibnizEquiv V} k dq1 dq2 v1 v2 :
    ✓ (juicy_view_frag k dq1 v1 ⋅ juicy_view_frag k dq2 v2) ↔ ✓ (dq1 ⋅ dq2) ∧ v1 = v2.
  Proof. unfold_leibniz. apply juicy_view_frag_op_valid. Qed.

  Lemma juicy_view_both_dfrac_validN n dp m k dq v :
    ✓{n} (juicy_view_auth dp m ⋅ juicy_view_frag k dq v) ↔
      ✓ dp ∧ ✓ dq ∧ coherent_loc m k (Some (dq, v)).
  Proof.
    rewrite /juicy_view_auth /juicy_view_frag.
    rewrite view_both_dfrac_validN coherent_rel_lookup.
    naive_solver.
  Qed.
  Lemma juicy_view_both_validN n m k dq v :
    ✓{n} (juicy_view_auth (DfracOwn Tsh) m ⋅ juicy_view_frag k dq v) ↔
      ✓ dq ∧ coherent_loc m k (Some (dq, v)).
  Proof. rewrite juicy_view_both_dfrac_validN. naive_solver done. Qed.
  Lemma juicy_view_both_dfrac_valid dp m k dq v :
    ✓ (juicy_view_auth dp m ⋅ juicy_view_frag k dq v) ↔
    ✓ dp ∧ ✓ dq ∧ coherent_loc m k (Some (dq, v)).
  Proof.
    rewrite /juicy_view_auth /juicy_view_frag.
    rewrite view_both_dfrac_valid. setoid_rewrite coherent_rel_lookup.
    split=>[[Hq Hm]|[Hq Hm]] //.
    split; first done. apply (Hm O).
  Qed.
  Lemma juicy_view_both_valid m k dq v :
    ✓ (juicy_view_auth (DfracOwn Tsh) m ⋅ juicy_view_frag k dq v) ↔
    ✓ dq ∧ coherent_loc m k (Some (dq, v)).
  Proof. rewrite juicy_view_both_dfrac_valid. naive_solver done. Qed.

  (** Frame-preserving updates *)
(*  Lemma juicy_view_alloc m k dq v :
    m !! k = None →
    ✓ dq →
    juicy_view_auth (DfracOwn Tsh) m ~~> juicy_view_auth (DfracOwn Tsh) (<[k := v]> m) ⋅ juicy_view_frag k dq v.
  Proof.
    intros Hfresh Hdq. apply view_update_alloc=>n bf Hrel j [df va] /=.
    rewrite lookup_op. destruct (decide (j = k)) as [->|Hne].
    - assert (bf !! k = None) as Hbf.
      { destruct (bf !! k) as [[df' va']|] eqn:Hbf; last done.
        specialize (Hrel _ _ Hbf). destruct Hrel as (v' & _ & _ & Hm).
        exfalso. rewrite Hm in Hfresh. done. }
      rewrite lookup_singleton Hbf.
      intros [= <- <-]. eexists. do 2 (split; first done).
      rewrite lookup_insert. done.
    - rewrite lookup_singleton_ne; last done.
      rewrite left_id=>Hbf.
      specialize (Hrel _ _ Hbf). destruct Hrel as (v' & ? & ? & Hm).
      eexists. do 2 (split; first done).
      rewrite lookup_insert_ne //.
  Qed.

  Lemma juicy_view_alloc_big m m' dq :
    m' ##ₘ m →
    ✓ dq →
    juicy_view_auth (DfracOwn Tsh) m ~~>
      juicy_view_auth (DfracOwn Tsh) (m' ∪ m) ⋅ ([^op map] k↦v ∈ m', juicy_view_frag k dq v).
  Proof.
    intros. induction m' as [|k v m' ? IH] using map_ind; decompose_map_disjoint.
    { rewrite big_opM_empty left_id_L right_id. done. }
    rewrite IH //.
    rewrite big_opM_insert // assoc.
    apply cmra_update_op; last done.
    rewrite -insert_union_l. apply (juicy_view_alloc _ k dq); last done.
    by apply lookup_union_None.
  Qed.

  Lemma juicy_view_delete m k v :
    juicy_view_auth (DfracOwn Tsh) m ⋅ juicy_view_frag k (DfracOwn Tsh) v ~~>
    juicy_view_auth (DfracOwn Tsh) (delete k m).
  Proof.
    apply view_update_dealloc=>n bf Hrel j [df va] Hbf /=.
    destruct (decide (j = k)) as [->|Hne].
    - edestruct (Hrel k) as (v' & _ & Hdf & _).
      { rewrite lookup_op Hbf lookup_singleton -Some_op. done. }
      exfalso. apply: dfrac_full_exclusive. apply Hdf.
    - edestruct (Hrel j) as (v' & ? & ? & Hm).
      { rewrite lookup_op lookup_singleton_ne // Hbf. done. }
      exists v'. do 2 (split; first done).
      rewrite lookup_delete_ne //.
  Qed.

  Lemma juicy_view_delete_big m m' :
    juicy_view_auth (DfracOwn Tsh) m ⋅ ([^op map] k↦v ∈ m', juicy_view_frag k (DfracOwn Tsh) v) ~~>
    juicy_view_auth (DfracOwn Tsh) (m ∖ m').
  Proof.
    induction m' as [|k v m' ? IH] using map_ind.
    { rewrite right_id_L big_opM_empty right_id //. }
    rewrite big_opM_insert //.
    rewrite [juicy_view_frag _ _ _ ⋅ _]comm assoc IH juicy_view_delete.
    rewrite -delete_difference. done.
  Qed.*)

  Global Instance exclusive_own_Tsh (v : agreeR V) : Exclusive(A := prodR dfracR (agreeR V)) (DfracOwn Tsh, v).
  Proof. apply _. Qed.

  Lemma coherent_store_outside : forall m b o bl m' loc r, Mem.storebytes m b o bl = Some m' ->
    ~adr_range (b, o) (length bl) loc ->
    coherent_loc m loc r ->
    coherent_loc m' loc r.
  Proof.
    intros ???????? Hrange (Hcontents & Hcur & Hmax & Halloc).
    split3; last split.
    - unfold contents_cohere, contents_at in *; intros.
      erewrite Mem.storebytes_mem_contents by eauto.
      destruct (eq_dec loc.1 b); [subst; rewrite Maps.PMap.gss | rewrite Maps.PMap.gso //; eauto].
      rewrite Mem.setN_other; eauto.
      { intros; unfold adr_range in *; destruct loc; simpl in *; lia. }
    - unfold access_cohere in *.
      erewrite <- storebytes_access; eauto.
    - unfold max_access_cohere, max_access_at in *.
      erewrite <- storebytes_access; eauto.
    - unfold alloc_cohere in *.
      erewrite Mem.nextblock_storebytes; eauto.
  Qed.

  Lemma get_setN : forall l z c i, (z <= i < z + length l)%Z -> Maps.ZMap.get i (Mem.setN l z c) = nth (Z.to_nat (i - z)) l Undef.
  Proof.
    induction l; simpl; intros; first lia.
    destruct (Z.to_nat (i - z)) eqn: Hi.
    - assert (i = z) as -> by lia.
      rewrite -> Mem.setN_other, Maps.ZMap.gss by lia; done.
    - rewrite IHl; last lia.
      replace (Z.to_nat (i - (z + 1))) with n by lia; done.
  Qed.

  Lemma coherent_store_in : forall m b o bl m' i dq v v', Mem.storebytes m b o bl = Some m' ->
    0 <= i < length bl -> memval_of (dq, v') = Some (nth i bl Undef) -> Mem.perm_order'' (perm_of_res (Some (dq, v))) (perm_of_res (Some (dq, v'))) ->
    coherent_loc m (b, o + Z.of_nat i)%Z (Some (dq, v)) ->
    coherent_loc m' (b, o + Z.of_nat i)%Z (Some (dq, v')).
  Proof.
    intros ??????????? Hv' Hperm (Hcontents & Hcur & Hmax & Halloc).
    split3; last split.
    - unfold contents_cohere, contents_at in *; simpl; intros ? Hv.
      rewrite Hv in Hv'; inv Hv'.
      erewrite Mem.storebytes_mem_contents by eauto.
      rewrite /= Maps.PMap.gss get_setN; last lia.
      replace (Z.to_nat _) with i by lia; done.
    - unfold access_cohere in *.
      erewrite <- storebytes_access by eauto.
      eapply perm_order''_trans; eauto.
    - unfold max_access_cohere, max_access_at in *.
      erewrite <- storebytes_access; eauto.
    - unfold alloc_cohere in *.
      erewrite Mem.nextblock_storebytes by eauto; intros.
      lapply Halloc; done.
  Qed.

  Lemma juicy_view_storebyte m m' k v v' b sh (Hsh : writable0_share sh) :
    Mem.storebytes m k.1 k.2 [b] = Some m' ->
    memval_of (DfracOwn sh, v') = Some b -> Mem.perm_order'' (perm_of_res (Some (DfracOwn sh, v))) (perm_of_res (Some (DfracOwn sh, v'))) ->
      juicy_view_auth (DfracOwn Tsh) m ⋅ juicy_view_frag k (DfracOwn sh) v ~~>
      juicy_view_auth (DfracOwn Tsh) m' ⋅ juicy_view_frag k (DfracOwn sh) v'.
  Proof.
    intros; apply view_update; intros ?? [Hv Hcoh].
(*    assert (bf !! k = None) as Hbf.
    { specialize (Hv k); rewrite lookup_op lookup_singleton in Hv.
      by apply exclusiveN_Some_l in Hv; last apply _. }*)
    split.
    { intros i; specialize (Hv i).
      rewrite !lookup_op in Hv |- *.
      destruct (decide (i = k)); last by rewrite !lookup_singleton_ne in Hv |- *.
      subst; rewrite !lookup_singleton in Hv |- *.
hnf.
(* relying on unreadable shares not being able to distinguish values *)

      subst; rewrite lookup_singleton Hbf //. }
    intros loc; specialize (Hcoh loc).
    rewrite /resource_at !lookup_op in Hcoh |- *.
    destruct (decide (loc = k)).
    - subst; rewrite !lookup_singleton !Hbf /= in Hcoh |- *.
      destruct k as (?, o); rewrite !elem_of_to_agree -(Z.add_0_r o) in Hcoh |- *.
      eapply (coherent_store_in _ _ _ _ _ O); eauto.
    - rewrite !lookup_singleton_ne in Hcoh |- *; [| done..].
      eapply coherent_store_outside; eauto.
      destruct loc as (?, o1), k as (?, o); intros [??]; subst; simpl in *.
      assert (o1 = o) by lia; congruence.
  Qed.

  Lemma lookup_singleton_list : forall {A} (l : list A) (f : A -> prodR dfracR (agreeR V)) k i, ([^op list] i↦v ∈ l, {[adr_add k (Z.of_nat i) := f v]}) !! i ≡
    if adr_range_dec k (Z.of_nat (length l)) i then f <$> (l !! (Z.to_nat (i.2 - k.2))) else None.
  Proof.
    intros.
    remember (rev l) as l'; revert dependent l; induction l'; simpl; intros.
    { destruct l; simpl; last by apply app_cons_not_nil in Heql'.
      rewrite lookup_empty; if_tac; auto. }
    apply (f_equal (@rev _)) in Heql'; rewrite rev_involutive in Heql'; subst; simpl.
    rewrite lookup_proper; last apply big_opL_snoc.
    rewrite lookup_op IHl'; last by rewrite rev_involutive.
    destruct k as (?, o), i as (?, o').
    if_tac; [|if_tac].
    - destruct H; subst; simpl.
      rewrite lookup_singleton_ne; last by rewrite /adr_add; intros [=]; lia.
      rewrite if_true; last by rewrite app_length; lia.
      rewrite lookup_app.
      by destruct (lookup_lt_is_Some_2 (rev l') (Z.to_nat (o' - o))) as (? & ->); first lia.
    - destruct H0 as [-> Hrange].
      rewrite app_length /= in Hrange.
      assert (o' = o + Z.of_nat (length (rev l')))%Z as -> by (rewrite /adr_range in H; lia).
      rewrite /adr_add lookup_singleton /= list_lookup_middle //; lia.
    - rewrite lookup_singleton_ne //.
      rewrite /adr_add /=; intros [=]; subst; contradiction H0.
      split; auto; rewrite app_length /=; lia.
  Qed.

  Lemma coherent_loc_ne n m k r1 r2 : ✓{n} r2 -> r1 ≡ r2 -> coherent_loc m k (resR_to_resource _ r1) -> coherent_loc m k (resR_to_resource _ r2).
  Proof.
    intros Hvalid.
    inversion 1 as [(?, ?) (?, ?) Heq|]; subst; last done.
    destruct Hvalid as [_ Hvalid].
    destruct Heq as [Hd Hv]; simpl in *; inv Hd.
    intros (Hcontents & Hcur & Hmax & Halloc); split3; last split.
    - intros ?; simpl.
      intros; apply Hcontents; simpl.
      eapply memval_of_ne, (elem_of_agree_ne n); eauto; done.
    - unfold access_cohere in *.
      erewrite perm_of_res_ne; eauto.
      apply (elem_of_agree_ne n); eauto; done.
    - done.
    - intros Hnext; specialize (Halloc Hnext); done.
  Qed.

  Lemma juicy_view_storebytes m m' k vl vl' bl
    (Hstore : Mem.storebytes m k.1 k.2 bl = Some m')
    (Hv' : Forall2 (fun v' b => memval_of (DfracOwn Tsh, v') = Some b) vl' bl) (Hperm : Forall2 (fun v v' => Mem.perm_order'' (perm_of_res (Some (DfracOwn Tsh, v))) (perm_of_res (Some (DfracOwn Tsh, v')))) vl vl') :
      juicy_view_auth (DfracOwn Tsh) m ⋅ ([^op list] i↦v ∈ vl, juicy_view_frag (adr_add k (Z.of_nat i)) (DfracOwn Tsh) v) ~~>
      juicy_view_auth (DfracOwn Tsh) m' ⋅ ([^op list] i↦v ∈ vl', juicy_view_frag (adr_add k (Z.of_nat i)) (DfracOwn Tsh) v).
  Proof.
    intros.
    rewrite -!big_opL_view_frag; apply view_update; intros ?? [Hv Hcoh].
    assert (forall i, if adr_range_dec k (Z.of_nat (length vl)) i then
      exists v v', vl !! (Z.to_nat (i.2 - k.2)) = Some v /\ vl' !! (Z.to_nat (i.2 - k.2)) = Some v' /\
      (([^op list] k0↦x ∈ vl, {[adr_add k (Z.of_nat k0) := (DfracOwn Tsh, to_agree x)]}) ⋅ bf) !! i ≡ Some (DfracOwn Tsh, to_agree v) /\
      (([^op list] k0↦x ∈ vl', {[adr_add k (Z.of_nat k0) := (DfracOwn Tsh, to_agree x)]}) ⋅ bf) !! i ≡ Some (DfracOwn Tsh, to_agree v')
      else
      ((([^op list] k0↦x ∈ vl, {[adr_add k (Z.of_nat k0) := (DfracOwn Tsh, to_agree x)]}) ⋅ bf) !! i ≡
       (([^op list] k0↦x ∈ vl', {[adr_add k (Z.of_nat k0) := (DfracOwn Tsh, to_agree x)]}) ⋅ bf) !! i)) as Hlookup.
    { intros i; specialize (Hv i).
      pose proof (Forall2_length _ _ _ Hperm) as Hlen.
      rewrite !lookup_op !lookup_singleton_list in Hv; if_tac.
      * destruct k as (?, o), i as (?, o'); destruct H; subst; simpl.
        destruct (lookup_lt_is_Some_2 vl (Z.to_nat (o' - o))) as (? & Hv1); first lia.
        destruct (lookup_lt_is_Some_2 vl' (Z.to_nat (o' - o))) as (? & Hv2); first lia.
        eexists _, _; split; eauto; split; eauto.
        rewrite !lookup_op !lookup_singleton_list.
        rewrite -Hlen; rewrite !if_true; [|split; auto..].
        rewrite Hv1 Hv2 /= in Hv |- *.
        apply exclusiveN_Some_l in Hv; last apply _.
        rewrite Hv //.
      * rewrite !lookup_op !lookup_singleton_list -Hlen !if_false //. }
    split; intros i; specialize (Hlookup i).
    - if_tac in Hlookup; last by rewrite -Hlookup.
      destruct Hlookup as (? & ? & ? & ? & ? & ->); done.
    - specialize (Hcoh i); unfold resource_at in *.
      if_tac in Hlookup.
      + destruct Hlookup as (? & ? & Hl1 & Hl2 & Hv1 & Hv2).
        eapply (coherent_loc_ne 0); [by rewrite Hv2 | done |].
        eapply (coherent_loc_ne 0) in Hcoh; last (by symmetry); last done.
        destruct k as (?, o), i as (?, o'), H; subst; simpl in *.
        replace o' with (o + Z.of_nat (Z.to_nat (o' - o)))%Z in Hcoh |- * by lia.
        eapply coherent_store_in; eauto.
        * erewrite <- Forall2_length, <- Forall2_length; eauto; lia.
        * rewrite Forall2_lookup in Hv'; specialize (Hv' (Z.to_nat (o' - o))).
          rewrite Hl2 in Hv'; inv Hv'.
          erewrite nth_lookup_Some by eauto.
          rewrite elem_of_to_agree //.
        * rewrite Forall2_lookup in Hperm; specialize (Hperm (Z.to_nat (o' - o))).
          rewrite Hl1 Hl2 in Hperm; inv Hperm.
          rewrite !elem_of_to_agree //.
      + eapply coherent_loc_ne; [| done |].
        { by rewrite -Hlookup. }
        eapply coherent_store_outside; eauto.
        destruct k; erewrite <- Forall2_length, <- Forall2_length; eauto.
  Qed.

  Lemma juicy_view_auth_persist dq m :
    juicy_view_auth dq m ~~> juicy_view_auth DfracDiscarded m.
  Proof. apply view_update_auth_persist. Qed.

(*  Lemma juicy_view_frag_persist k dq v :
    juicy_view_frag k dq v ~~> juicy_view_frag k DfracDiscarded v.
  Proof.
    apply view_update_frag=>m n bf Hrel.
    eapply coherent_mono; first apply Hrel; auto.
    apply (@cmra_monoN_r (juicy_view_fragUR V)).
    rewrite singleton_includedN_l lookup_singleton.
    eexists; split; first done.
    rewrite Some_includedN pair_includedN; right.
    split; last by apply to_agree_includedN.
    eexists.
Search DfracDiscarded includedN.
    hnf.
    Search to_agree includedN.
    rewrite lookup_singleton.
Search includedN "singleton".
    rewrite lookup_includedN.
    Search op includedN.
    rewrite lookup_op. destruct (decide (j = k)) as [->|Hne].
    - rewrite lookup_singleton.
      edestruct (Hrel k ((dq, to_agree v) ⋅? bf !! k)) as (v' & Hdf & Hva & Hm).
      { rewrite lookup_op lookup_singleton.
        destruct (bf !! k) eqn:Hbf; by rewrite Hbf. }
      rewrite Some_op_opM. intros [= Hbf].
      exists v'. rewrite assoc; split; last done.
      destruct (bf !! k) as [[df' va']|] eqn:Hbfk; rewrite Hbfk in Hbf; clear Hbfk.
      + simpl in *. rewrite -cmra.pair_op in Hbf.
        move:Hbf=>[= <- <-]. split; first done.
        eapply cmra_discrete_valid.
        eapply (dfrac_discard_update _ _ (Some df')).
        apply cmra_discrete_valid_iff. done.
      + simpl in *. move:Hbf=>[= <- <-]. split; done.
    - rewrite lookup_singleton_ne //.
      rewrite left_id=>Hbf.
      edestruct (Hrel j) as (v'' & ? & ? & Hm).
      { rewrite lookup_op lookup_singleton_ne // left_id. done. }
      simpl in *. eexists. do 2 (split; first done). done.
  Qed.*)

  (** Typeclass instances *)
  Global Instance juicy_view_frag_core_id k dq v : OraCoreId dq → OraCoreId (juicy_view_frag k dq v).
  Proof. apply _. Qed.

  Global Instance juicy_view_ora_discrete : OfeDiscrete V → OraDiscrete (juicy_viewR V).
  Proof. apply _. Qed.

  Global Instance juicy_view_frag_mut_is_op dq dq1 dq2 k v :
    IsOp dq dq1 dq2 →
    IsOp' (juicy_view_frag k dq v) (juicy_view_frag k dq1 v) (juicy_view_frag k dq2 v).
  Proof. rewrite /IsOp' /IsOp => ->. apply juicy_view_frag_op. Qed.
End lemmas.

(*
(** Functor *)
Program Definition juicy_viewURF (F : oFunctor) : uorarFunctor := {|
  uorarFunctor_car A _ B _ := juicy_viewUR (oFunctor_car F A B);
  uorarFunctor_map A1 _ A2 _ B1 _ B2 _ fg :=
    viewO_map (rel:=coherent_rel (oFunctor_car F A1 B1))
              (rel':=coherent_rel (oFunctor_car F A2 B2))
              (gmapO_map (oFunctor_map F fg))
              (gmapO_map (prodO_map cid (agreeO_map (oFunctor_map F fg))))
|}.
Next Obligation.
  intros K ?? F A1 ? A2 ? B1 ? B2 ? n f g Hfg.
  apply viewO_map_ne.
  - apply gmapO_map_ne, oFunctor_map_ne. done.
  - apply gmapO_map_ne. apply prodO_map_ne; first done.
    apply agreeO_map_ne, oFunctor_map_ne. done.
Qed.
Next Obligation.
  intros K ?? F A ? B ? x; simpl in *. rewrite -{2}(view_map_id x).
  apply (view_map_ext _ _ _ _)=> y.
  - rewrite /= -{2}(map_fmap_id y).
    apply map_fmap_equiv_ext=>k ??.
    apply oFunctor_map_id.
  - rewrite /= -{2}(map_fmap_id y).
    apply map_fmap_equiv_ext=>k [df va] ?.
    split; first done. simpl.
    rewrite -{2}(agree_map_id va).
    eapply agree_map_ext; first by apply _.
    apply oFunctor_map_id.
Qed.
Next Obligation.
  intros K ?? F A1 ? A2 ? A3 ? B1 ? B2 ? B3 ? f g f' g' x; simpl in *.
  rewrite -view_map_compose.
  apply (view_map_ext _ _ _ _)=> y.
  - rewrite /= -map_fmap_compose.
    apply map_fmap_equiv_ext=>k ??.
    apply oFunctor_map_compose.
  - rewrite /= -map_fmap_compose.
    apply map_fmap_equiv_ext=>k [df va] ?.
    split; first done. simpl.
    rewrite -agree_map_compose.
    eapply agree_map_ext; first by apply _.
    apply oFunctor_map_compose.
Qed.
Next Obligation.
  intros K ?? F A1 ? A2 ? B1 ? B2 ? fg; simpl.
  (* [apply] does not work, probably the usual unification probem (Coq #6294) *)
  apply: view_map_ora_morphism; [apply _..|]=> n m f.
  intros Hrel k [df va] Hf. move: Hf.
  rewrite !lookup_fmap.
  destruct (f !! k) as [[df' va']|] eqn:Hfk; rewrite Hfk; last done.
  simpl=>[= <- <-].
  specialize (Hrel _ _ Hfk). simpl in Hrel. destruct Hrel as (v & Hagree & Hdval & Hm).
  exists (oFunctor_map F fg v).
  rewrite Hm. split; last by auto.
  rewrite Hagree. rewrite agree_map_to_agree. done.
Qed.

Global Instance juicy_viewURF_contractive (K : Type) `{Countable K} F :
  oFunctorContractive F → uorarFunctorContractive (juicy_viewURF K F).
Proof.
  intros ? A1 ? A2 ? B1 ? B2 ? n f g Hfg.
  apply viewO_map_ne.
  - apply gmapO_map_ne. apply oFunctor_map_contractive. done.
  - apply gmapO_map_ne. apply prodO_map_ne; first done.
    apply agreeO_map_ne, oFunctor_map_contractive. done.
Qed.

Program Definition juicy_viewRF (K : Type) `{Countable K} (F : oFunctor) : OrarFunctor := {|
  orarFunctor_car A _ B _ := juicy_viewR K (oFunctor_car F A B);
  orarFunctor_map A1 _ A2 _ B1 _ B2 _ fg :=
    viewO_map (rel:=coherent_rel K (oFunctor_car F A1 B1))
              (rel':=coherent_rel K (oFunctor_car F A2 B2))
              (gmapO_map (K:=K) (oFunctor_map F fg))
              (gmapO_map (K:=K) (prodO_map cid (agreeO_map (oFunctor_map F fg))))
|}.
Solve Obligations with apply juicy_viewURF.

Global Instance juicy_viewRF_contractive (K : Type) `{Countable K} F :
  oFunctorContractive F → OrarFunctorContractive (juicy_viewRF K F).
Proof. apply juicy_viewURF_contractive. Qed.*)

Global Typeclasses Opaque juicy_view_auth juicy_view_frag.
