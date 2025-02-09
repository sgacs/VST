(* Do not edit this file, it was generated automatically *)
Require Import VST.floyd.proofauto.
Require Import VST.progs64.append.

#[export] Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.
Definition t_struct_list := Tstruct _list noattr.

Lemma not_bot_nonidentity : forall sh,  sh <> Share.bot -> sepalg.nonidentity sh.
Proof.
   intros.
   unfold sepalg.nonidentity. unfold not.
   intros. apply identity_share_bot in H0. contradiction.
Qed.
Lemma nonidentity_not_bot : forall sh, sepalg.nonidentity sh -> sh <> Share.bot.
Proof.
   intros. unfold sepalg.nonidentity. unfold not. intros. apply H. rewrite H0. apply bot_identity.    
Qed.
#[export] Hint Resolve not_bot_nonidentity : core.
#[export] Hint Resolve nonidentity_not_bot : core.

Section Spec.

Context  `{!default_VSTGS Σ}.

Fixpoint listrep (sh: share)
            (contents: list val) (x: val) : mpred :=
 match contents with
 | h::hs =>
              ∃ y:val,
                data_at sh t_struct_list (h,y) x ∗ listrep sh hs y
 | nil => ⌜x = nullval⌝ ∧ emp
 end.

Arguments listrep sh contents x : simpl never.

Lemma listrep_local_facts:
  forall sh contents p,
     listrep sh contents p ⊢
     ⌜is_pointer_or_null p ∧ (p=nullval <-> contents=nil)⌝.
Proof.
intros.
revert p; induction contents; 
  unfold listrep; fold listrep; intros. entailer!. tauto.
Intros y. entailer!.
split; intro. subst p. destruct H; contradiction. inv H2.
Qed.



Lemma listrep_valid_pointer:
  forall sh contents p,
  sepalg.nonidentity sh ->
   listrep sh contents p ⊢ valid_pointer p.
Proof.
 destruct contents; unfold listrep; fold listrep; intros; Intros; subst.
 auto with valid_pointer.
 Intros y.
 apply sepcon_valid_pointer1.
 apply data_at_valid_ptr; auto.
 simpl; computable.
Qed.

Lemma listrep_null: forall sh contents,
    listrep sh contents nullval ⊣⊢ ⌜contents=nil⌝ ∧ emp.
Proof.
destruct contents; unfold listrep; fold listrep.
autorewrite with norm. auto.
apply bi.equiv_entails_2.
Intros y. entailer!. destruct H; contradiction.
Intros. discriminate.
Qed.

Lemma is_pointer_or_null_not_null:
 forall x, is_pointer_or_null x -> x <> nullval -> isptr x.
Proof.
intros.
 destruct x; try contradiction. hnf in H; subst i. contradiction H0; reflexivity.
 apply I.
Qed.

Definition append_spec :=
 DECLARE _append
  WITH sh : share, x: val, y: val, s1: list val, s2: list val
  PRE [ tptr t_struct_list , tptr t_struct_list]
     PROP(writable_share sh)
     PARAMS (x; y) GLOBALS()
     SEP (listrep sh s1 x; listrep sh s2 y)
  POST [ tptr t_struct_list ]
    ∃ r: val,
     PROP()
     RETURN (r)
     SEP (listrep sh (s1++s2) r).

Definition Gprog : funspecs :=   ltac:(with_library prog [ append_spec ]).

Hint Resolve listrep_local_facts : saturate_local.
Hint Extern 1 (listrep _ _ _ ⊢ valid_pointer _) =>
    (simple apply listrep_valid_pointer; now auto) : valid_pointer.

Section Proof1.

Lemma body_append: semax_body Vprog Gprog f_append append_spec.
Proof.
start_function.
forward_if.
*
 subst x.
 forward.
 rewrite listrep_null. Intros; subst.
 Exists y.
 entailer!!.
 simpl; auto.
*
 forward.
 destruct s1 as [ | v s1']; unfold listrep at 1; fold listrep.
 { Intros. contradiction. }
 Intros u.
 remember (v::s1') as s1.
 forward.
 forward_while
      (∃ a: val, ∃ s1b: list val, ∃ t: val, ∃ u: val,
            PROP ()
            LOCAL (temp _x x; temp _t t; temp _u u; temp _y y)
            SEP (listrep sh (a::s1b++s2) t -∗ listrep sh (s1++s2) x;
                   data_at sh t_struct_list (a,u) t;
                   listrep sh s1b u;
                   listrep sh s2 y))%assert.
+ (* current assertion implies loop invariant *)
   Exists v s1' x u.
   entailer!. simpl. cancel_wand.
+ (* loop test is safe to execute *)
   entailer!!.
+ (* loop body preserves invariant *)
   clear v Heqs1.
   destruct s1b; unfold listrep at 3; fold listrep. Intros. contradiction.
   Intros z.
   forward.
   forward.
   Exists (v,s1b,u0,z). unfold fst, snd.
   simpl app.
   entailer!!.
   iIntros "[Ha Hb]". iIntros.
   iApply "Ha".
   unfold listrep; fold listrep. iExists u0; iFrame.
+ (* after the loop *)
   clear v s1' Heqs1.
   forward.
   simpl. (* TODO this simpl wasn't needed. maybe store_tac_no_hint in forward1 is broken? *)
   forward.
   rewrite (proj1 H2 (eq_refl _)).
   Exists x.
   simpl app.
   clear.
   entailer!!.
   unfold listrep at 3; fold listrep. Intros.
   iIntros "(Ha & Hb & Hc & Hd)".
   iApply "Ha".
   unfold listrep at -1; fold listrep. iExists y; iFrame.
Qed.

End Proof1.

Section Proof2.

Definition lseg (sh: share) (contents: list val) (x z: val) : mpred :=
  ∀ cts2:list val, listrep sh cts2 z -∗ listrep sh (contents++cts2) x.

Lemma body_append2: semax_body Vprog Gprog f_append append_spec.
Proof.
start_function.
forward_if.
*
 subst x. rewrite listrep_null. Intros; subst.
 forward.
 Exists y; simpl; entailer!.
*
 forward.
 destruct s1 as [ | v s1']; unfold listrep; fold listrep. Intros; contradiction.
 Intros u.
 remember (v::s1') as s1.
 forward.
 forward_while
      (∃ s1a: list val, ∃ a: val, ∃ s1b: list val, ∃ t: val, ∃ u: val,
            PROP (s1 = s1a ++ a :: s1b)
            LOCAL (temp _x x; temp _t t; temp _u u; temp _y y)
            SEP (lseg sh s1a x t;
                   data_at sh t_struct_list (a,u) t;
                   listrep sh s1b u;
                   listrep sh s2 y))%assert.
+ (* current assertion implies loop invariant *)
   Exists (@nil val) v s1' x u.  entailer!!.
   unfold lseg. iIntros. simpl. auto.
+ (* loop test is safe to execute *)
   entailer!!.
+ (* loop body preserves invariant *)
   clear v Heqs1. subst s1.
   destruct s1b; unfold listrep; fold listrep. Intros; contradiction.
   Intros z.
   forward.
   forward.
   Exists (s1a++[a],v,s1b,u0,z). unfold fst, snd.
   rewrite <- !app_assoc. simpl app.
   entailer!!.
   unfold lseg.
   rewrite bi.sep_comm.
   clear.
   iIntros "[H1 H2]".
   iIntros (cts2) "H3".
   iSpecialize ("H2" $! (a :: cts2)).
   rewrite -app_assoc.
   iApply ("H2").
   unfold listrep at -1; fold listrep. iExists u0. iFrame.
 + (* after the loop *)
   forward. simpl. forward.
   Exists x. entailer!!.
   destruct H3 as [? _]. specialize (H3 (eq_refl _)). subst s1b.
   unfold listrep at 1.  Intros. autorewrite with norm.  rewrite H0. rewrite <- app_assoc. simpl app.
   unfold lseg.
   iIntros "(H1 & H2 & H3)".
   iApply ("H1" $! (a :: s2)).
   unfold listrep at 2; fold listrep. iExists y; iFrame.
Qed.

End Proof2.

Section Proof3.  (*************** inductive lseg *******************)

Fixpoint lseg2 (sh: share)
            (contents: list val) (x z: val) : mpred :=
 match contents with
 | h::hs => ⌜x<>z⌝ ∧ 
              ∃ y:val,
                data_at sh t_struct_list (h,y) x ∗ lseg2 sh hs y z
 | nil => ⌜x = z /\ is_pointer_or_null x⌝ ∧ emp
 end.

Arguments lseg2 sh contents x z : simpl never.
Notation lseg := lseg2.

Lemma lseg_local_facts:
  forall sh contents p q,
     lseg sh contents p q ⊢
     ⌜is_pointer_or_null p /\ is_pointer_or_null q /\ (p=q <-> contents=nil)⌝.
Proof.
intros.
revert p; induction contents; intros; simpl; unfold lseg; fold lseg.
{ normalize. }
Intros y.
entailer!.
intuition discriminate.
Qed.

Hint Resolve lseg_local_facts : saturate_local.

Lemma lseg_valid_pointer:
  forall sh contents p ,
   sepalg.nonidentity sh ->
   lseg sh contents p nullval ⊢ valid_pointer p.
Proof.
 destruct contents; unfold lseg; fold lseg; intros. entailer!.
 Intros *.
 auto with valid_pointer.
Qed.

Hint Extern 1 (lseg _ _ _ nullval ⊢ valid_pointer _) =>
    (simple apply lseg_valid_pointer; now auto) : valid_pointer.

Lemma lseg_eq: forall sh contents x,
    lseg sh contents x x ⊣⊢ ⌜contents=nil /\ is_pointer_or_null x⌝ ∧ emp.
Proof.
intros.
destruct contents; unfold lseg; fold lseg.
- apply and_mono_iff; auto. apply bi.pure_iff. intuition.
- iSplit. 
  + iIntros "[%H1 H2]". contradiction.
  + iIntros "[%H1 H2]". destruct H1. discriminate.
Qed.

Lemma lseg_null: forall sh contents,
    lseg sh contents nullval nullval ⊣⊢ ⌜contents=nil⌝ ∧ emp.
Proof.
intros.
 rewrite lseg_eq.
 apply and_mono_iff; auto.
 apply bi.pure_iff; intuition.
Qed.

Lemma lseg_cons: forall sh (v u x: val) (s: list val),
   readable_share sh ->
 data_at sh t_struct_list (v, u) x ∗ lseg sh s u nullval
 ⊢ lseg sh [v] x u ∗ lseg sh s u nullval.
Proof.
intros.
     unfold lseg at 2. Exists u.
     entailer.
     destruct s; unfold lseg at 1; fold lseg; entailer.
Qed.

Lemma lseg_cons': forall sh (v u x a b: val),
   readable_share sh ->
 data_at sh t_struct_list (v, u) x ∗ data_at sh t_struct_list (a,b) u
 ⊢ lseg sh [v] x u ∗ data_at sh t_struct_list (a,b) u.
Proof.
intros.
     unfold lseg. Exists u.
     entailer!.
Qed.

Lemma lseg_app': forall sh s1 s2 (a w x y z: val),
   readable_share sh ->
   (lseg sh s1 w x ∗ lseg sh s2 x y) ∗ data_at sh t_struct_list (a,z) y ⊢
   lseg sh (s1++s2) w y ∗ data_at sh t_struct_list (a,z) y.
Proof.
 intros.
 revert w; induction s1; intro; simpl.
 unfold lseg at 1. entailer!.
 unfold lseg at 1 3; fold lseg. Intros j; Exists j.
 entailer.
 sep_apply (IHs1 j).
 cancel.
Qed.
 
Lemma lseg_app_null: forall sh s1 s2 (w x: val),
   readable_share sh ->
   lseg sh s1 w x ∗ lseg sh s2 x nullval ⊢
   lseg sh (s1++s2) w nullval.
Proof.
 intros.
 revert w; induction s1; intro; simpl.
 unfold lseg at 1. entailer!.
 unfold lseg at 1 3; fold lseg. Intros j; Exists j.
 entailer.
 sep_apply (IHs1 j).
 cancel.
Qed.

Lemma lseg_app: forall sh s1 s2 a s3 (w x y z: val),
   readable_share sh ->
   lseg sh s1 w x ∗ lseg sh s2 x y ∗ lseg sh (a::s3) y z ⊢
   lseg sh (s1++s2) w y ∗ lseg sh (a::s3) y z.
Proof.
 intros.
 unfold lseg at 3 5; fold lseg.
 Intros u; Exists u. rewrite prop_true_andp //.
 sep_apply (lseg_app' sh s1 s2 a w x y u); auto.
 cancel.
Qed.

Lemma listrep_lseg_null :
 ∀ sh s p, listrep sh s p ⊣⊢ lseg sh s p nullval.
Proof.
intros.
revert p.
induction s; intros.
unfold lseg, listrep; apply bi.equiv_entails_2; entailer!.
unfold lseg, listrep; fold lseg; fold listrep.
apply bi.equiv_entails_2; Intros y; Exists y; rewrite IHs; entailer!.
Qed.

Lemma body_append3: semax_body Vprog Gprog f_append append_spec.
Proof.
start_function.
rewrite -> listrep_lseg_null in * |- *.
forward_if.
*
 subst x. rewrite lseg_null. Intros. subst.
 forward.
 Exists y; simpl; entailer!.
*
 forward.
 destruct s1 as [ | v s1']; unfold lseg at 1; fold lseg.
 Intros. contradiction H.
 Intros u.
 clear - SH.
 remember (v::s1') as s1.
 forward.
 forward_while
      (∃ s1a: list val, ∃ a: val, ∃ s1b: list val, ∃ t: val, ∃ u: val,
            PROP (s1 = s1a ++ a :: s1b)
            LOCAL (temp _x x; temp _t t; temp _u u; temp _y y)
            SEP (lseg sh s1a x t; 
                   data_at sh t_struct_list (a,u) t;
                   lseg sh s1b u nullval; 
                   lseg sh s2 y nullval))%assert.
 + (* current assertion implies loop invariant *)
     Exists (@nil val) v s1' x u.
     subst s1. rewrite lseg_eq listrep_lseg_null.
     entailer.
(*     sep_apply (lseg_cons sh v u x s1'); auto. *)
 + (* loop test is safe to execute *)
     entailer!!.
 + (* loop body preserves invariant *)
    destruct s1b; unfold lseg at 2; fold lseg.
    Intros. contradiction.
    Intros z.
    forward.
    forward.
    Exists (s1a++a::nil, v0, s1b,u0,z). unfold fst, snd.
    simpl app; rewrite <- app_assoc.
    entailer.
    sep_apply (lseg_cons' sh a u0 t v0 z); auto.
    sep_apply (lseg_app' sh s1a [a] v0 x t u0 z); auto.
    cancel.
 + (* after the loop *)
    clear v s1' Heqs1.
    subst. rewrite lseg_eq. Intros. subst. 
    forward.
    forward.
    Exists x.
    entailer!!.
    sep_apply (lseg_cons sh a y t s2); auto.
    sep_apply (lseg_app_null sh [a] s2 t y); auto.
    rewrite <- app_assoc.
    sep_apply (lseg_app_null sh s1a ([a]++s2) x t); auto.
    rewrite listrep_lseg_null //.
Qed.

End Proof3.
End Spec.
