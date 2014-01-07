Require Import compcert.common.Events.
Require Import compcert.common.Memory.
Require Import compcert.lib.Coqlib.
Require Import compcert.common.Values.
Require Import compcert.lib.Maps.
Require Import compcert.lib.Integers.
Require Import compcert.common.AST.

Require Import compcert.common.Globalenvs.

Require Import compcert.lib.Axioms.

Require Import sepcomp.mem_lemmas. (*needed for definition of mem_forward etc*)
Require Import sepcomp.core_semantics.
Require Import sepcomp.effect_semantics.
Require Import sepcomp.StructuredInjections.

Definition vis mu := fun b => locBlocksSrc mu b || frgnBlocksSrc mu b.
  
Inductive reach (m:mem) (B:block -> Prop): list (block * Z) -> block -> Prop :=
  reach_nil: forall b, B b -> reach m B nil b
| reach_cons: forall b L b' z off n,
                     reach m B L b' ->
                     Mem.perm m b' z Cur Readable ->
                     ZMap.get z (PMap.get b' (Mem.mem_contents m)) = 
                        Pointer b off n ->
              reach m B ((b',z)::L) b.

Fixpoint reach' (m:mem) (B:block -> Prop) (L:list (block * Z)): block -> Prop:=
  match L with
    nil => B
  | l::L => match l with 
             (b',z) => match ZMap.get z (PMap.get b' (Mem.mem_contents m))
                       with Pointer b off n => fun bb => bb = b /\
                                               Mem.perm m b' z Cur Readable /\
                                               reach' m B L b'
                           | _ => fun bb => False
                       end
            end
  end.

Lemma reach_reach': forall m B L b1, reach m B L b1 <-> reach' m B L b1.
Proof. intros m B L.
  induction L; simpl; split; intros.
    inv H. trivial. constructor. trivial.
  destruct a as [b' z]. destruct (IHL b') as [IHa IHb]; clear IHL.
    inv H. rewrite H6.
    destruct (Mem.perm_dec m b' z Cur Readable); try contradiction; simpl.
    split; trivial. eauto.
  destruct a as [b' z]. 
    remember (ZMap.get z (Mem.mem_contents m) !! b') as v.
    destruct v; try inv H. apply eq_sym in Heqv.
    destruct H1. apply IHL in H0.
      econstructor; try eassumption.
Qed.

(*Fixpoint reach'' (m:mem) (B:block -> bool) (L:list (block * Z)): block -> bool:=
  match L with
    nil => B
  | l::L => match l with 
             (b',z) => match ZMap.get z (PMap.get b' (Mem.mem_contents m))
                       with Pointer b off n => fun bb => eq_block bb b &&
                                               Mem.perm_dec m b' z Cur Readable  &&
                                               reach' m B L b'
                           | _ => fun bb => false
                       end
            end
  end.

Lemma reach_reach': forall m L B b1, reach m (fun b => B b = true) L b1 <-> reach' m B L b1 = true.
Proof. intros m L.
  induction L; simpl; split; intros.
    inv H. trivial. constructor. trivial.
  destruct a as [b' z]. destruct (IHL B b') as [IHa IHb]; clear IHL.
    inv H. rewrite H6.
    destruct (Mem.perm_dec m b' z Cur Readable); try contradiction; simpl.
    destruct (eq_block b1 b1); simpl. apply IHa. apply H3.
    exfalso. apply n0; trivial. 
  destruct a as [b' z]. 
    remember (ZMap.get z (Mem.mem_contents m) !! b') as v.
    specialize (IHL (fun bb=> B bb = Mem.perm_dec m b' z Cur Readable && reach' m B L b') b').
    destruct v; try inv H. apply eq_sym in Heqv.
    destruct (eq_block b1 b); simpl in *; try inv H1.
      econstructor; try eassumption. 
      destruct IHL. clear H.
        apply (IHL (Mem.perm_dec m b' z Cur Readable && reach' m B L b')). b').
      apply andb_true_iff in H1; destruct H1. 
      apply IHb in H0. clear IHa IHb.
      econstructor; try eassumption.
Qed.    
*)

Lemma reach_inject: forall m1 m2 j (J: Mem.inject j m1 m2)
                 L1 b1 B1 (R: reach m1 B1 L1 b1) B2
                 (HB: forall b, B1 b -> exists jb d, j b = Some(jb,d) /\ B2 jb),
                 exists b2 L2 d2, j b1 = Some(b2,d2) /\ reach m2 B2 L2 b2.
Proof. intros.
  induction R.
    destruct (HB _ H) as [jb [d [Jb B]]].
    exists jb, nil, d. split; trivial. constructor. assumption.
  destruct IHR as [b2' [L2' [d2' [J' R2']]]].
    clear R HB.         
    specialize (Mem.mi_memval _ _ _ (Mem.mi_inj _ _ _ J) _ _ _ _ J' H).
    intros. rewrite H0 in H1.
    inv H1.
    exists b2, ((b2',(z + d2'))::L2'), delta.
    split. assumption.
    eapply reach_cons. apply R2'.
       eapply Mem.perm_inject. apply J'. apply J. apply H.
       apply eq_sym. apply H6.
Qed.

Lemma reach_mono: forall B1 B2 (HB : forall b, B1 b = true -> B2 b = true)
                         m b L1 (R : reach m (fun bb : block => B1 bb = true) L1 b),
                  exists L, reach m (fun bb : block => B2 bb = true) L b.
Proof. intros.
  induction R; simpl in *.
    exists nil. constructor.  eauto. 
  destruct IHR as [L2 R2]. 
    eexists. eapply reach_cons; eassumption.
Qed.

(*
Parameter reachable : mem -> list block -> block -> bool.
Axioms reachAX: forall m B b, reachable m B b = true 
                    <-> exists L, reach m (fun bb => In bb B) L b.

Lemma reachable_inject: forall m1 m2 j (J: Mem.inject j m1 m2) B1 B2
                 (HB: forall b, In b B1 -> exists jb d, j b = Some(jb,d) /\ In jb B2)
                 b1 (R: reachable m1 B1 b1 = true),
                 exists b2 d, j b1 = Some(b2,d) /\ reachable m2 B2 b2 = true.
Proof.
  intros. apply reachAX in R. destruct R as [L1 R].
  destruct (reach_inject _ _ _ J _ _ _ R _ HB) as [b2 [L2 [off [J2 R2]]]].
  exists b2, off. split; trivial.
    apply reachAX. exists L2; assumption.
Qed.
*)

Parameter REACH : mem -> (block -> bool) -> block -> bool.
Axioms REACHAX: forall m B b, REACH m B b = true 
                    <-> exists L, reach m (fun bb => B bb = true) L b.

Lemma REACH_nil: forall m B b, B b = true -> REACH m B b = true.
Proof. intros. apply REACHAX.
 exists nil. constructor. assumption.
Qed.

Lemma REACH_cons: forall m B b b' z off n,
                     REACH m B b' = true ->
                     Mem.perm m b' z Cur Readable ->
                     ZMap.get z (PMap.get b' (Mem.mem_contents m)) = 
                        Pointer b off n ->
                  REACH m B b = true.
Proof. intros.
  apply REACHAX in H. destruct H as [L HL].
  apply REACHAX. eexists.
  eapply reach_cons; eassumption.
Qed. 

Lemma REACH_inject: forall m1 m2 j (J: Mem.inject j m1 m2) B1 B2
                 (HB: forall b, B1 b = true -> exists jb d, j b = Some(jb,d) /\ B2 jb = true)
                 b1 (R: REACH m1 B1 b1 = true),
                 exists b2 d, j b1 = Some(b2,d) /\ REACH m2 B2 b2 = true.
Proof.
  intros. apply REACHAX in R. destruct R as [L1 R].
  destruct (reach_inject _ _ _ J _ _ _ R _ HB) as [b2 [L2 [off [J2 R2]]]].
  exists b2, off. split; trivial.
    apply REACHAX. exists L2; assumption.
Qed.
           
Lemma REACH_mono: forall B1 B2 (HB: forall b, B1 b = true -> B2 b = true) m b
                  (R: REACH m B1 b = true), REACH m B2 b = true.
Proof. intros. rewrite REACHAX in *.
  destruct R as [L1 R].
  apply (reach_mono _ _ HB _ _ _ R).
Qed.

Definition replace_locals (mu:SM_Injection) pSrc' pTgt': SM_Injection :=
  match mu with 
    Build_SM_Injection locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern =>
    Build_SM_Injection locBSrc locBTgt pSrc' pTgt' local extBSrc extBTgt fSrc fTgt extern 
  end.
(*typically, we have forall b, pSrc b -> pSrc' b and forall b, pTgt b -> pTgt' b,
  i.e. only reclassify private entries as public*)

Lemma replace_locals_wd: forall mu (WD: SM_wd mu) pSrc' pTgt'
         (SRC: forall b1, pSrc' b1 = true -> 
               exists b2 d, local_of mu b1 = Some(b2,d) /\ pTgt' b2=true)
         (TGT: forall b, pTgt' b = true -> locBlocksTgt mu b = true),
      SM_wd (replace_locals mu pSrc' pTgt'). 
Proof. intros.
  destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *. 
  constructor; simpl; try apply WD.
    intros. rewrite H. apply (SRC _ H).
    assumption.
Qed.

Lemma replace_locals_extern: forall mu pubSrc' pubTgt',
      extern_of (replace_locals mu pubSrc' pubTgt') = extern_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_local: forall mu pubSrc' pubTgt',
      local_of (replace_locals mu pubSrc' pubTgt') = local_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_unknown: forall mu pubSrc' pubTgt',
      unknown_of (replace_locals mu pubSrc' pubTgt') = unknown_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_foreign: forall mu pubSrc' pubTgt',
      foreign_of (replace_locals mu pubSrc' pubTgt') = foreign_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_pub: forall mu pubSrc' pubTgt',
      pub_of (replace_locals mu pubSrc' pubTgt') = 
          (fun b => if pubSrc' b then local_of mu b else None).
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_pub': forall mu pubSrc' pubTgt'
      (P: forall b, pubBlocksSrc mu b = true -> pubSrc' b = true)
      b (B: pubBlocksSrc mu b = true),
      pub_of (replace_locals mu pubSrc' pubTgt') b = pub_of mu b.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
rewrite B, (P _ B). trivial.
Qed.

Lemma replace_locals_as_inj: forall mu pubSrc' pubTgt',
      as_inj (replace_locals mu pubSrc' pubTgt') = as_inj mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_shared: forall mu pubSrc' pubTgt',
      shared_of (replace_locals mu pubSrc' pubTgt') = 
      join (foreign_of mu) (fun b => if pubSrc' b then local_of mu b else None).
Proof. intros. unfold shared_of, join; simpl.
rewrite replace_locals_foreign.
rewrite replace_locals_pub.
trivial.
Qed.

Lemma replace_locals_DOM: forall mu pubSrc' pubTgt',
      DOM (replace_locals mu pubSrc' pubTgt') = DOM mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_RNG: forall mu pubSrc' pubTgt',
      RNG (replace_locals mu pubSrc' pubTgt') = RNG mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed. 

Lemma replace_locals_DomSrc: forall mu pubSrc' pubTgt',
      DomSrc (replace_locals mu pubSrc' pubTgt') = DomSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_DomTgt: forall mu pubSrc' pubTgt',
      DomTgt (replace_locals mu pubSrc' pubTgt') = DomTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed. 

Lemma replace_locals_locBlocksSrc: forall mu pubSrc' pubTgt',
      locBlocksSrc (replace_locals mu pubSrc' pubTgt') = locBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_extBlocksTgt: forall mu pubSrc' pubTgt',
      extBlocksTgt (replace_locals mu pubSrc' pubTgt') = extBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_extBlocksSrc: forall mu pubSrc' pubTgt',
      extBlocksSrc (replace_locals mu pubSrc' pubTgt') = extBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_locBlocksTgt: forall mu pubSrc' pubTgt',
      locBlocksTgt (replace_locals mu pubSrc' pubTgt') = locBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_frgnBlocksSrc: forall mu pubSrc' pubTgt',
      frgnBlocksSrc (replace_locals mu pubSrc' pubTgt') = frgnBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_frgnBlocksTgt: forall mu pubSrc' pubTgt',
      frgnBlocksTgt (replace_locals mu pubSrc' pubTgt') = frgnBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_pubBlocksSrc: forall mu pubSrc' pubTgt',
      pubBlocksSrc (replace_locals mu pubSrc' pubTgt') = pubSrc'.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_locals_pubBlocksTgt: forall mu pubSrc' pubTgt',
      pubBlocksTgt (replace_locals mu pubSrc' pubTgt') = pubTgt'.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Definition replace_externs (mu:SM_Injection) fSrc' fTgt': SM_Injection :=
  match mu with 
    Build_SM_Injection locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern =>
    Build_SM_Injection locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc' fTgt' extern
  end.
(*typically, we have forall b, fSrc b -> fSrc' b and forall b, fTgt b -> fTgt' b,
  i.e. only reclassify unknown entries as foreign*)

Lemma replace_externs_wd: forall mu (WD: SM_wd mu) fSrc' fTgt'
         (SRC: forall b1, fSrc' b1 = true -> 
               exists b2 d, extern_of mu b1 = Some(b2,d) /\ fTgt' b2=true)
         (TGT: forall b, fTgt' b = true -> extBlocksTgt mu b = true),
      SM_wd (replace_externs mu fSrc' fTgt'). 
Proof. intros.
  destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *. 
  constructor; simpl; try apply WD.
    intros. rewrite H. apply (SRC _ H).
    assumption.
Qed.

Lemma replace_externs_extern: forall mu frgSrc' frgTgt',
      extern_of (replace_externs mu frgSrc' frgTgt') = extern_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_foreign: forall mu frgSrc' frgTgt',
      foreign_of (replace_externs mu frgSrc' frgTgt') = 
      fun b : block => if frgSrc' b then extern_of mu b else None.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_local: forall mu frgSrc' frgTgt',
      local_of (replace_externs mu frgSrc' frgTgt') = local_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_priv: forall mu frgSrc' frgTgt',
      priv_of (replace_externs mu frgSrc' frgTgt') = priv_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_pub: forall mu frgSrc' frgTgt',
      pub_of (replace_externs mu frgSrc' frgTgt') = pub_of mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_as_inj: forall mu frgSrc' frgTgt',
      as_inj (replace_externs mu frgSrc' frgTgt') = as_inj mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_DOM: forall mu frgSrc' frgTgt',
      DOM (replace_externs mu frgSrc' frgTgt') = DOM mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_RNG: forall mu frgSrc' frgTgt',
      RNG (replace_externs mu frgSrc' frgTgt') = RNG mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed. 

Lemma replace_externs_DomSrc: forall mu frgSrc' frgTgt',
      DomSrc (replace_externs mu frgSrc' frgTgt') = DomSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_DomTgt: forall mu frgSrc' frgTgt',
      DomTgt (replace_externs mu frgSrc' frgTgt') = DomTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed. 

Lemma replace_externs_locBlocksSrc: forall mu frgSrc' frgTgt',
      locBlocksSrc (replace_externs mu frgSrc' frgTgt') = locBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_locBlocksTgt: forall mu frgSrc' frgTgt',
      locBlocksTgt (replace_externs mu frgSrc' frgTgt') = locBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_extBlocksSrc: forall mu frgSrc' frgTgt',
      extBlocksSrc (replace_externs mu frgSrc' frgTgt') = extBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_extBlocksTgt: forall mu frgSrc' frgTgt',
      extBlocksTgt (replace_externs mu frgSrc' frgTgt') = extBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_frgnBlocksSrc: forall mu fSrc' fTgt',
      frgnBlocksSrc (replace_externs mu fSrc' fTgt') = fSrc'.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_frgnBlocksTgt: forall mu fSrc' fTgt',
      frgnBlocksTgt (replace_externs mu fSrc' fTgt') = fTgt'.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_pubBlocksSrc: forall mu frgSrc' frgTgt',
      pubBlocksSrc (replace_externs mu frgSrc' frgTgt') = pubBlocksSrc mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Lemma replace_externs_pubBlocksTgt: forall mu frgSrc' frgTgt',
      pubBlocksTgt (replace_externs mu frgSrc' frgTgt') = pubBlocksTgt mu.
Proof. intros. 
destruct mu as [locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern]; simpl in *.
reflexivity.
Qed.

Definition getBlocks (V:list val) (b: block): bool :=
   in_dec eq_block b 
    (fold_right (fun v L => match v with Vptr b' z => b'::L | _ => L end) nil V).

Lemma getBlocksD: forall v V b, 
  getBlocks (v:: V) b = 
    match v with
      Vptr b' _  => orb (eq_block b' b) (getBlocks V b)
    | _ => getBlocks V b
   end.
Proof. intros.
  destruct v; simpl; try reflexivity.
  unfold getBlocks. simpl.
  destruct (eq_block b0 b); simpl. trivial.
  destruct (in_dec eq_block b
    (fold_right
       (fun (v : val) (L : list block) =>
        match v with
        | Vundef => L
        | Vint _ => L
        | Vlong _ => L
        | Vfloat _ => L
        | Vptr b' _ => b' :: L
        end) nil V)). trivial. trivial.  
Qed.

Lemma getBlocksD_nil: forall b, 
  getBlocks nil b = false.
Proof. intros.
  reflexivity.
Qed.

Lemma getBlocks_char: forall V b, getBlocks V b = true <-> 
   exists off, In (Vptr b off) V.
Proof.
  intros V. induction V; simpl; intros.
     unfold getBlocks; simpl. split; intros. inv H. destruct H. contradiction.
  rewrite getBlocksD.
  destruct a; simpl in *; destruct (IHV b); clear IHV.
      split; intros. destruct (H H1). exists x; right; trivial.
         apply H0. destruct H1 as [n [X | X]]. inv X. exists n; trivial.
      split; intros. destruct (H H1). exists x; right; trivial.
         apply H0. destruct H1 as [n [X | X]]. inv X. exists n; trivial.
      split; intros. destruct (H H1). exists x; right; trivial.
         apply H0. destruct H1 as [n [X | X]]. inv X. exists n; trivial.
      split; intros. destruct (H H1). exists x; right; trivial.
         apply H0. destruct H1 as [n [X | X]]. inv X. exists n; trivial.
      split; intros. 
         apply orb_true_iff in H1. 
           destruct H1. exists i; left. clear H H0.
             destruct (eq_block b0 b); subst. trivial. inv H1.
           destruct (H H1). exists x; right; trivial. 
         apply orb_true_iff. destruct H1 as [n [X | X]].
            left. inv X. destruct (eq_block b b); subst. trivial. exfalso. apply n0; trivial.
            right. apply H0. exists n; trivial.
Qed. 

Lemma getBlocks_inject: forall j vals1 vals2
                       (ValInjMu : Forall2 (val_inject j) vals1 vals2)
                       b (B: getBlocks vals1 b = true),
      exists jb d, j b = Some (jb, d) /\ getBlocks vals2 jb = true.
Proof. intros. apply getBlocks_char in B. destruct B as [off INN].
   destruct (forall2_val_inject_D _ _ _ ValInjMu _ INN) as [v2 [ValInj INN2]].
   inv ValInj.
   exists b2, delta. split; trivial.
   apply getBlocks_char. eexists. apply INN2.
Qed.

Definition REACH_closed m (X: Values.block -> bool) : Prop :=
  (forall b, REACH m X b = true -> X b = true).

Definition mapped (j:meminj) b : bool :=
  match j b with None => false | Some _ => true end.

Lemma mappedD_true : forall j b (M: mapped j b = true),
                     exists p, j b = Some p.
Proof. intros.
  unfold mapped in M.
  remember (j b) as d. destruct d; inv M. exists p; trivial.
Qed.
Lemma mappedD_false : forall j b (M: mapped j b = false),
                      j b = None.
Proof. intros.
  unfold mapped in M.
  remember (j b) as d. destruct d; inv M. trivial.
Qed.
Lemma mappedI_true : forall j b p (J: j b = Some p),
                      mapped j b = true.
Proof. intros.
  unfold mapped; rewrite J; trivial.
Qed.
Lemma mappedI_false : forall j b (J:j b = None),
                       mapped j b = false.
Proof. intros.
  unfold mapped; rewrite J; trivial.
Qed.
Lemma mapped_charT: forall j b, (mapped j b = true) <-> (exists p, j b = Some p).
Proof. intros.
  split; intros.
    apply mappedD_true; assumption.
  destruct H. eapply mappedI_true; eassumption.
Qed.
Lemma mapped_charF: forall j b, (mapped j b = false) <-> (j b = None).
Proof. intros.
  split; intros.
    apply mappedD_false; assumption.
    apply mappedI_false; assumption.
Qed.

Lemma inject_mapped: forall j m1 m2 (Inj12: Mem.inject j m1 m2) k
          (RC: REACH_closed m1 (mapped k))
          (INC: inject_incr k j),
      Mem.inject k m1 m2.
Proof. intros.
split; intros.
  split; intros.
     eapply Inj12; try eassumption. eapply INC; eassumption.
     eapply Inj12; try eassumption. eapply INC; eassumption.
     specialize (Mem.mi_memval _ _ _ (Mem.mi_inj _ _ _ Inj12) b1).
        rewrite (INC _ _ _ H). intros.
        specialize (H1 _ _ _ (eq_refl _) H0).
        inv H1; try constructor.
        assert (R: REACH m1 (mapped k) b0 = true).
           apply eq_sym in H2.
           eapply REACH_cons; try eassumption.
           apply REACH_nil. eapply mappedI_true; eassumption.
        specialize (RC _ R). 
          destruct (mappedD_true _ _ RC) as [[bb dd] RR]; clear RC.
          rewrite (INC _ _ _ RR) in H4; inv H4. 
        econstructor; try eassumption. trivial.
   remember (k b) as d.
     destruct d; apply eq_sym in Heqd; trivial.
     destruct p. apply INC in Heqd.
     exfalso. apply H. apply (Mem.valid_block_inject_1 _ _ _ _ _ _ Heqd Inj12).
   apply INC in H. eapply Inj12; eauto.
   intros b1 b1'; intros. 
     apply INC in H0; apply INC in H1.
     eapply Inj12; eassumption.
   apply INC in H.
     eapply Inj12; eassumption.
Qed.

Definition restrict (j: meminj) (X:block -> bool) : meminj :=
  fun b => if X b then j b else None.

Lemma restrictD_Some: forall j X b1 b2 d (R:restrict j X b1 = Some(b2,d)),
                      j b1 = Some(b2,d) /\ X b1 = true.
Proof. intros.
  unfold restrict in R.
  remember (X b1) as dd.
  destruct dd; inv R. split; trivial.
Qed.
Lemma restrictI_Some: forall j X b b2 d (J:j b = Some(b2,d)) 
                            (Hb: X b = true),
                      restrict j X b = Some(b2,d).
Proof. intros.
  unfold restrict. rewrite Hb; trivial.
Qed.
Lemma restrictD_None: forall j X b1 b2 d (R:restrict j X b1 = None)
                      (J: j b1 = Some(b2,d)), X b1 = false.
Proof. intros.
  unfold restrict in R. rewrite J in R.
  remember (X b1) as dd.
  destruct dd; inv R; trivial.
Qed.
Lemma restrictD_None': forall j X b1 (R:restrict j X b1 = None),
                         j b1 = None \/ 
                        (exists b2 d, j b1 =Some(b2,d) /\ X b1 = false).
Proof. intros.
  remember (j b1) as d.
  destruct d; try (left; reflexivity).
  destruct p; apply eq_sym in Heqd. right.
  rewrite (restrictD_None _ _ _ _ _ R Heqd).
  exists b, z; split; trivial.
Qed.
Lemma restrictI_None: forall j X b (Hb: j b = None \/ X b = false),
                      restrict j X b = None.
Proof. intros.
  unfold restrict.
  remember (X b) as d.
  destruct d; trivial.
  destruct Hb; trivial; congruence.
Qed.

Lemma join_restrict: forall j k X, 
      join (restrict j X) (restrict k X) = restrict (join j k) X.
Proof. intros.
  unfold join, restrict. extensionality b.
  remember (X b) as d.
  destruct d; trivial.
Qed.

Lemma restrict_outside: forall j X
        (HX: forall b1 b2 d, j b1 = Some(b2, d) -> X b1 = true),
      restrict j X = j.
Proof. intros. unfold restrict.
  extensionality b.
  remember (X b) as d.
  destruct d; trivial.
  remember (j b) as q.
  destruct q; trivial.
  apply eq_sym in Heqq. destruct p.
  apply HX in Heqq. congruence.
Qed.

Lemma restrict_incr: forall j X, inject_incr (restrict j X) j.
Proof. intros j X b b2 d Hb. eapply restrictD_Some; eassumption. Qed.

Lemma restrict_com: forall j X Y,
      restrict (restrict j X) Y = restrict (restrict j Y) X.
Proof. intros. unfold restrict.
  extensionality b.
  destruct (Y b); destruct (X b); trivial.
Qed.

Lemma restrict_nest: forall j X Y 
         (HXY: forall b, Y b = true -> X b = true),
      restrict (restrict j X) Y = restrict j Y.
Proof. intros. unfold restrict.
  extensionality b.
  remember (Y b) as d.
  destruct d; trivial. apply eq_sym in Heqd.
  rewrite (HXY _ Heqd). trivial.
Qed.
Lemma restrict_nest': forall j X Y 
         (HXY: forall b, Y b = true -> X b = true),
      restrict (restrict j Y) X = restrict j Y.
Proof. intros. rewrite restrict_com.
  apply restrict_nest; assumption. 
Qed.

Lemma restrict_val_inject: forall j val1 val2
     (Inj : val_inject j val1 val2)
     X (HR: forall b, getBlocks (val1::nil) b = true -> X b = true),
   val_inject (restrict j X) val1 val2.
Proof. intros.
  inv Inj; try constructor.
      econstructor; trivial.
        eapply restrictI_Some; try eassumption.
         apply HR; simpl. rewrite getBlocksD.
         remember (eq_block b1 b1) .
         destruct s. trivial. exfalso. apply n; trivial.
Qed. 
Lemma restrict_forall_vals_inject: forall j vals1 vals2
     (Inj : Forall2 (val_inject j) vals1 vals2)
     X (HR: forall b, getBlocks vals1 b = true -> X b = true),
 Forall2 (val_inject (restrict j X)) vals1 vals2.
Proof. intros.
  induction Inj. constructor.
  constructor.
    apply restrict_val_inject. assumption. 
       intros. apply HR.
         rewrite getBlocksD in H0. 
         rewrite getBlocksD_nil in H0.
         rewrite getBlocksD.
         destruct x; try congruence.
         apply orb_true_iff in H0. destruct H0; intuition.
   apply IHInj. intros. apply HR.
      rewrite getBlocksD. rewrite H0.
      destruct x; trivial. intuition.
Qed.

Lemma val_inject_restrictD: forall j v v' X
       (V: val_inject (restrict j X) v v'),
     val_inject j v v'.
Proof. intros.
  inv V; try econstructor.
  eapply restrict_incr.  apply H. 
trivial. 
Qed.
 
Lemma forall_vals_inject_restrictD: forall j vals1 vals2 X
     (Inj : Forall2 (val_inject (restrict j X)) vals1 vals2),
 Forall2 (val_inject j) vals1 vals2.
Proof. intros.
  induction Inj. constructor.
  constructor; trivial.
    eapply val_inject_restrictD; eassumption.
Qed.

Lemma restrict_mapped_closed: forall j m X 
      (RC: REACH_closed m (mapped j))
      (RX: REACH_closed m X),
      REACH_closed m (mapped (restrict j X)).
Proof. intros.
  intros b Hb. 
  apply REACHAX in Hb.
  destruct Hb as [L HL].
  generalize dependent b.
  induction L; simpl; intros; inv HL. 
     assumption.
  specialize (IHL _ H1); clear H1.
    destruct (mappedD_true _ _ IHL) as [[bb' dd'] M']; clear IHL.
    unfold restrict in M'.
    remember (X b') as d; destruct d; inv M'.
    assert (Rb: REACH m (mapped j) b = true).
      eapply REACH_cons; try eassumption.
      apply REACH_nil. eapply mappedI_true; eassumption. 
    specialize (RC _ Rb).
      destruct (mappedD_true _ _ RC) as [[bb dd] M]; clear RC.
    assert (Xb: REACH m X b = true).
      eapply REACH_cons; try eassumption.
      apply REACH_nil. rewrite Heqd; trivial.
    specialize (RX _ Xb).       
    eapply mappedI_true. unfold restrict. rewrite M, RX. reflexivity.
Qed.

Lemma restrict_mapped_closed_triv: forall j m X, 
      REACH_closed m (fun b => mapped j b && X b) = 
      REACH_closed m (mapped (restrict j X)).
Proof. intros.
  assert ((fun b => mapped j b && X b) = (mapped (restrict j X))).
    extensionality b. unfold mapped, restrict.
    destruct (j b); simpl; destruct (X b); trivial.
  rewrite H. trivial.
Qed.

Lemma REACH_closed_intersection: forall m X Y
        (HX: REACH_closed m X) (HY: REACH_closed m Y), 
      REACH_closed m (fun b => X b && Y b).
Proof. intros. intros b Hb.
  rewrite REACHAX in Hb.
  destruct Hb as [L HL].
  generalize dependent b.
  induction L; simpl; intros; inv HL; trivial.
  specialize (IHL _ H1); clear H1.
  apply andb_true_iff in IHL. destruct IHL.
  apply andb_true_iff.
  split.
    apply HX. eapply REACH_cons; try eassumption.
      apply REACH_nil; eassumption.
    apply HY. eapply REACH_cons; try eassumption.
      apply REACH_nil; eassumption.
Qed.

Lemma REACH_closed_union: forall m X Y
        (HX: REACH_closed m X) (HY: REACH_closed m Y), 
      REACH_closed m (fun b => X b || Y b).
Proof. intros. intros b Hb.
  rewrite REACHAX in Hb.
  destruct Hb as [L HL].
  generalize dependent b.
  induction L; simpl; intros; inv HL; trivial.
  specialize (IHL _ H1); clear H1.
  apply orb_true_iff in IHL.
  apply orb_true_iff.
  destruct IHL.
    left.
    apply HX. eapply REACH_cons; try eassumption.
      apply REACH_nil; eassumption.
  right. apply HY. eapply REACH_cons; try eassumption.
      apply REACH_nil; eassumption.
Qed.

Lemma inject_REACH_closed: forall j m1 m2 (Inj: Mem.inject j m1 m2),
      REACH_closed m1 (mapped j).
Proof. intros. intros b Hb.
  destruct (REACH_inject _ _ _ Inj (mapped j)  (fun b => true)) 
    with (b1:=b) as [b2 [dd [ZZ _]]].
    intros; simpl.
      destruct (mappedD_true _ _ H) as [[bb d] J]; clear H.
      exists bb, d; split; trivial.
    assumption.
  eapply mappedI_true; eassumption. 
Qed.

Lemma inject_restrict: forall j m1 m2 X
        (INJ : Mem.inject j m1 m2)
        (RC : REACH_closed m1 X),
      Mem.inject (restrict j X) m1 m2.
Proof. intros.
  eapply inject_mapped; try eassumption.
    eapply restrict_mapped_closed; try eassumption.
    eapply inject_REACH_closed; try eassumption.
  apply restrict_incr.
Qed.

(*The blocks explicitly exported via call arguments, plus the already shared blocks*)
Definition exportedSrc mu vals b := orb (getBlocks vals b) (sharedSrc mu b).
Definition exportedTgt mu vals b := orb (getBlocks vals b) (sharedTgt mu b).

Lemma exported_inject: forall mu (WD: SM_wd mu) vals1 vals2
          (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b
          (SRC: exportedSrc mu vals1 b = true ),
        exists jb d, as_inj mu b = Some (jb, d)
                  /\ exportedTgt mu vals2 jb = true.
Proof. intros. unfold exportedSrc in SRC. unfold exportedTgt.
  apply orb_true_iff in SRC.
  destruct SRC as [SRC | SRC].
   destruct (getBlocks_inject _ _ _ ValInjMu _ SRC) as [b2 [d [J G]]].
   exists b2, d. rewrite J, G. intuition.
  destruct (shared_SrcTgt _ WD _ SRC) as [b2 [d [J G]]].
   exists b2, d. rewrite (shared_in_all _ WD _ _ _ J).
      rewrite G. intuition.
Qed.

Lemma REACH_shared_of: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (shared_of mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (shared_of mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
        B (HB: forall b b2 d, shared_of mu b = Some(b2,d) -> B b2 = true),
      exists b2 d, shared_of mu b1 = Some (b2, d) /\ 
                   REACH m2 (fun b => orb (getBlocks vals2 b) (B b)) b2 = true.
Proof. intros.
 eapply (REACH_inject _ _ _ MemInjMu); try eassumption.
 clear R. simpl; intros.
 apply orb_true_iff in H.
 destruct H.
   destruct (getBlocks_inject _ _ _ ValInjMu _ H) as [b2 [d [J G]]].
   exists b2, d. rewrite J, G. intuition.
 apply sharedSrc_iff in H. destruct H as [jb [delta SH]].
   specialize (HB _ _ _ SH).
   exists jb, delta. 
   intuition.
Qed.

Lemma REACH_as_inj: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
        B (HB: forall b b2 d, shared_of mu b = Some(b2,d) -> B b2 = true),
      exists b2 d, as_inj mu b1 = Some (b2, d) /\ 
                   REACH m2 (fun b => orb (getBlocks vals2 b) (B b)) b2 = true.
Proof. intros.
 eapply (REACH_inject _ _ _ MemInjMu); try eassumption.
 clear R. simpl; intros.
 apply orb_true_iff in H.
 destruct H.
   destruct (getBlocks_inject _ _ _ ValInjMu _ H) as [b2 [d [J G]]].
   exists b2, d. rewrite J, G. intuition.
 apply sharedSrc_iff in H. destruct H as [jb [delta SH]].
   specialize (HB _ _ _ SH).
   apply shared_in_all in SH; trivial.
   exists jb, delta. 
   intuition.
Qed.

Lemma REACH_local: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
         (locBSrc : locBlocksSrc mu b1 = true),
      exists b2 d, local_of mu b1 = Some (b2, d).
Proof. intros.
  destruct (REACH_as_inj _ WD _ _ _ _ MemInjMu ValInjMu 
            _ R (fun b => true)) as [b2 [d [ASINJ RR]]].
    trivial.
  exists b2, d.
  assert (noExt:= locBlocksSrc_externNone _ WD _ locBSrc).
  destruct (joinD_Some _ _ _ _ _ ASINJ). congruence.
  apply H.
Qed.
 
Lemma REACH_extern: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1 
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
         (locBSrc : locBlocksSrc mu b1 = false),
      exists b2 d, extern_of mu b1 = Some (b2, d).
Proof. intros.
  destruct (REACH_as_inj _ WD _ _ _ _ MemInjMu ValInjMu 
            _ R (fun b => true)) as [b2 [d [ASINJ RR]]].
    trivial.
  exists b2, d.
  destruct (joinD_Some _ _ _ _ _ ASINJ). assumption.
  destruct H.
  destruct (local_DomRng _ WD _ _ _ H0) as [ZZ _]; rewrite ZZ in locBSrc.
  intuition.
Qed.

(*The following six or so results are key lemmas about REACH - they say
  that blocks exported in SRC are injected, to blocks exported by TGT,
  preserving the locBlocks-structure, ie distinction betwene public and
  foreign*)
Lemma REACH_as_inj_REACH: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true),
      exists b2 d, as_inj mu b1 = Some (b2, d) /\ 
                   REACH m2 (exportedTgt mu vals2) b2 = true.
Proof. intros.
  destruct (REACH_as_inj _ WD _ _ _ _ MemInjMu ValInjMu _ R (fun b => true))
       as [b2 [d [ASI _]]]. trivial.
  exists b2, d. split; trivial.
  destruct (REACH_inject _ _ _ MemInjMu _ _ 
      (exported_inject _ WD _ _ ValInjMu) _ R)
   as [bb2 [dd [ASI' RR]]].
  rewrite ASI' in ASI. inv ASI.
  assumption.
Qed.

Lemma REACH_local_REACH: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
         (locBSrc : locBlocksSrc mu b1 = true),
      exists b2 d, local_of mu b1 = Some (b2, d) /\ 
                   REACH m2 (exportedTgt mu vals2) b2 = true.
Proof. intros.
  destruct (REACH_as_inj_REACH _ WD _ _ _ _ MemInjMu ValInjMu 
            _ R) as [b2 [d [ASINJ RR]]].
  exists b2, d. split; trivial.
  assert (noExt:= locBlocksSrc_externNone _ WD _ locBSrc).
  destruct (joinD_Some _ _ _ _ _ ASINJ). congruence.
  apply H.
Qed.

Lemma REACH_local_REACH': forall mu m1 vals1  b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
        (WD: SM_wd mu) m2 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2)
        (locBSrc : locBlocksSrc mu b1 = true) b2 d
        (LOC: local_of mu b1 = Some (b2, d)), 
     REACH m2 (exportedTgt mu vals2) b2 = true.
Proof. intros.
  destruct (REACH_local_REACH _ WD _ _ _ _ MemInjMu ValInjMu _ R locBSrc)
  as [bb [dd [LL RR]]]. rewrite LL in LOC. inv LOC. trivial.
Qed.

Lemma REACH_extern_REACH: forall mu (WD: SM_wd mu) m1 m2 vals1 vals2 
        (MemInjMu : Mem.inject (as_inj mu) m1 m2)
        (ValInjMu : Forall2 (val_inject (as_inj mu)) vals1 vals2) b1
        (R : REACH m1 (exportedSrc mu vals1) b1 = true)
         (locBSrc : locBlocksSrc mu b1 = false),
      exists b2 d, extern_of mu b1 = Some (b2, d) /\ 
                   REACH m2 (exportedTgt mu vals2) b2 = true.
Proof. intros.
  destruct (REACH_as_inj_REACH _ WD _ _ _ _ MemInjMu ValInjMu 
            _ R) as [b2 [d [ASINJ RR]]].
  exists b2, d. split; trivial.
  destruct (joinD_Some _ _ _ _ _ ASINJ).
    apply H.
  destruct H as [_ H]. 
    destruct (local_DomRng _ WD _ _ _ H) as [ZZ _]; rewrite ZZ in locBSrc.
    intuition.
Qed.

Goal forall m1 mu (WD: SM_wd mu) vals b, pubBlocksSrc mu b = true ->
           REACH m1 (exportedSrc mu vals) b = true.
Proof. intros. apply REACH_nil.
  apply orb_true_iff. right. apply pubSrc_shared; trivial. 
Qed.

Definition local_out_of_reach mu (m : mem) (b : block) (ofs : Z): Prop := 
  locBlocksTgt mu b = true /\ 
  forall b0 delta, local_of mu b0 = Some (b, delta) -> 
                  (~ Mem.perm m b0 (ofs - delta) Max Nonempty \/
                   pubBlocksSrc mu b0 = false).

Definition genv2blocksBool {F V : Type} (ge : Genv.t F V):= 
  (fun b =>
      match Genv.invert_symbol ge b with
        Some id => true
      | None => false
      end,
   fun b => match Genv.find_var_info ge b with
                  Some gv => true
                | None => false
            end).

Lemma genvs_domain_eq_match_genvsB: forall {F1 V1 F2 V2:Type} 
  (ge1: Genv.t F1 V1) (ge2: Genv.t F2 V2),
  genvs_domain_eq ge1 ge2 -> genv2blocksBool ge1 = genv2blocksBool ge2.
Proof. intros F1 V1 F2 V2 ge1 ge2.
  unfold genvs_domain_eq, genv2blocksBool. simpl; intros. 
  destruct H. 
  f_equal; extensionality b.
    destruct (H b); clear H.
    remember (Genv.invert_symbol ge1 b) as d.
      destruct d; apply eq_sym in Heqd.
      apply Genv.invert_find_symbol in Heqd.
        destruct H1. eexists; eassumption.
        apply Genv.find_invert_symbol in H.
        rewrite H. trivial.
    remember (Genv.invert_symbol ge2 b) as q.
     destruct q; trivial; apply eq_sym in Heqq.
      apply Genv.invert_find_symbol in Heqq.
        destruct H2. eexists; eassumption.
        apply Genv.find_invert_symbol in H.
        rewrite H in Heqd. discriminate.
   destruct (H0 b); clear H0.
     remember (Genv.find_var_info ge1 b) as d.
       destruct d; apply eq_sym in Heqd.
         destruct H1. eexists; reflexivity.
         rewrite H0. trivial.
       remember (Genv.find_var_info ge2 b) as q.
         destruct q; apply eq_sym in Heqq; trivial.
           destruct H2. eexists; reflexivity.
           discriminate.
Qed.

Lemma genv2blocksBool_char1: forall F V (ge : Genv.t F V) b,
     (fst (genv2blocksBool ge)) b = true <-> fst (genv2blocks ge) b.
Proof. intros.
  remember (genv2blocksBool ge) as X.
  destruct X as [f g]; simpl. 
  remember (genv2blocks ge) as Y.
  destruct Y as [f' g']; simpl.
  unfold genv2blocksBool in HeqX. inv HeqX.
  unfold genv2blocks in HeqY. inv HeqY.
  remember (Genv.invert_symbol ge b) as d.
  destruct d; apply eq_sym in Heqd.
    split; intros; trivial.  
    exists i. rewrite (Genv.invert_find_symbol _ _ Heqd). trivial.
  split; intros; try congruence.
    destruct H.
    apply Genv.find_invert_symbol in H. congruence.
Qed.

Lemma genv2blocksBool_char2: forall F V (ge : Genv.t F V) b,
     (snd (genv2blocksBool ge)) b = true <-> snd (genv2blocks ge) b.
Proof. intros.
  remember (genv2blocksBool ge) as X.
  destruct X as [f g]; simpl. 
  remember (genv2blocks ge) as Y.
  destruct Y as [f' g']; simpl.
  unfold genv2blocksBool in HeqX. inv HeqX.
  unfold genv2blocks in HeqY. inv HeqY.
  remember (Genv.find_var_info ge b) as d.
  destruct d; apply eq_sym in Heqd.
    split; intros; trivial.  
    exists g; trivial.
  split; intros; try congruence.
    destruct H. congruence.
Qed.

Lemma genv2blocksBool_char1': forall F V (ge : Genv.t F V) b,
     (fst (genv2blocksBool ge)) b = false <-> ~ fst (genv2blocks ge) b.
Proof. intros.
  split; intros.
    intros N. apply genv2blocksBool_char1 in N. congruence.
  remember (fst (genv2blocksBool ge) b) as d.
  destruct d; trivial. apply eq_sym in Heqd.
    apply genv2blocksBool_char1 in Heqd. congruence.
Qed.

Lemma genv2blocksBool_char2': forall F V (ge : Genv.t F V) b,
     (snd (genv2blocksBool ge)) b = false <-> ~ snd (genv2blocks ge) b.
Proof. intros.
  split; intros.
    intros N. apply genv2blocksBool_char2 in N. congruence.
  remember (snd (genv2blocksBool ge) b) as d.
  destruct d; trivial. apply eq_sym in Heqd.
    apply genv2blocksBool_char2 in Heqd. congruence.
Qed.

Definition isGlobalBlock {F V : Type} (ge : Genv.t F V) :=
  fun b => (fst (genv2blocksBool ge)) b || (snd (genv2blocksBool ge)) b.

Lemma restrict_preserves_globals: forall {F V} (ge:Genv.t F V) j X
  (PG : meminj_preserves_globals ge j)
  (Glob : forall b, isGlobalBlock ge b = true -> X b = true),
meminj_preserves_globals ge (restrict j X).
Proof. intros.
  apply meminj_preserves_genv2blocks in PG.
  destruct PG as [PGa [PGb PGc]].
  apply meminj_preserves_genv2blocks.
  split; intros.
    specialize (PGa _ H).
    apply restrictI_Some. assumption.
    apply Glob. 
    unfold isGlobalBlock.
      apply genv2blocksBool_char1 in H. rewrite H. intuition.
  split; intros.
    specialize (PGb _ H).
    apply restrictI_Some. assumption.
    apply Glob. 
    unfold isGlobalBlock.
      apply genv2blocksBool_char2 in H. rewrite H. intuition.
  destruct (restrictD_Some _ _ _ _ _ H0) as [AU XX]; clear H0.
     apply (PGc _ _ _ H AU). 
Qed.

Lemma genvs_domain_eq_isGlobal: forall {F1 V1 F2 V2} ge1 ge2
                       (DomainEQ: @genvs_domain_eq F1 V1 F2 V2 ge1 ge2),
       isGlobalBlock ge1 = isGlobalBlock ge2.
Proof. intros.
  destruct DomainEQ.
  extensionality b. unfold isGlobalBlock.
  remember (fst (genv2blocksBool ge1) b) as d.
  destruct d; apply eq_sym in Heqd.
    apply genv2blocksBool_char1 in Heqd. 
    apply H in Heqd.
    apply genv2blocksBool_char1 in Heqd.
    rewrite Heqd. trivial.
  apply genv2blocksBool_char1' in Heqd.
    remember (fst (genv2blocksBool ge2) b) as q.
    destruct q; apply eq_sym in Heqq.  
      apply genv2blocksBool_char1 in Heqq.
      apply H in Heqq. contradiction.
  clear Heqd Heqq.
  remember (snd (genv2blocksBool ge1) b) as d.
  destruct d; apply eq_sym in Heqd.
    apply genv2blocksBool_char2 in Heqd. 
    apply H0 in Heqd.
    apply genv2blocksBool_char2 in Heqd.
    rewrite Heqd. trivial.
  apply genv2blocksBool_char2' in Heqd.
    remember (snd (genv2blocksBool ge2) b) as q.
    destruct q; apply eq_sym in Heqq.  
      apply genv2blocksBool_char2 in Heqq.
      apply H0 in Heqq. contradiction.
   trivial.
Qed.
    
Lemma meminj_preserves_globals_isGlobalBlock: forall {F V} (g: Genv.t F V)
               j (PG: meminj_preserves_globals g j)
               b (GB: isGlobalBlock g b = true),
      j b = Some (b, 0).
Proof. intros.
  unfold isGlobalBlock in GB.
  apply meminj_preserves_genv2blocks in PG.
  destruct PG as [PGa [PGb PGc]].
  apply orb_true_iff in GB.
  destruct GB.
    apply genv2blocksBool_char1 in H. apply (PGa _ H).
    apply genv2blocksBool_char2 in H. apply (PGb _ H).
Qed.

Lemma meminj_preserves_globals_initSM: forall {F1 V1} (ge: Genv.t F1 V1) j
                  (PG : meminj_preserves_globals ge j) DomS DomT X Y,
      meminj_preserves_globals ge (extern_of (initial_SM DomS DomT X Y j)).
Proof. intros. apply PG. Qed.

Lemma meminj_preserves_globals_init_REACH_frgn:
      forall {F1 V1} (ge: Genv.t F1 V1) j
             (PG : meminj_preserves_globals ge j) DomS DomT m R Y
             (HR: forall b, isGlobalBlock ge b = true -> R b = true),
      (forall b, isGlobalBlock ge b = true -> 
                 frgnBlocksSrc (initial_SM DomS DomT (REACH m R) Y j) b = true).
Proof. intros.
  unfold initial_SM; simpl.
  apply REACH_nil. apply (HR _ H).
Qed.

Lemma REACH_is_closed: forall R m1, 
  REACH_closed m1 (fun b : block => REACH m1 R b).
Proof. intros. unfold REACH_closed. intros.
  apply REACHAX. apply REACHAX in H. destruct H as [L HL].
  generalize dependent b. 
  induction L; intros; simpl in *; inv HL.
     apply REACHAX in H. apply H.
  specialize (IHL _ H1). destruct IHL as [LL HLL].
    eexists. eapply reach_cons; eassumption.
Qed.

(*Generic proof that the inital structured injection satisfies 
  the match_genv, match_wd and match_valid conditions of the LSR*)
Lemma core_initial_wd : forall {F1 V1 F2 V2} (ge1: Genv.t F1 V1) (ge2: Genv.t F2 V2) 
                               vals1 m1 j vals2 m2 DomS DomT
          (MInj: Mem.inject j m1 m2)
          (VInj: Forall2 (val_inject j) vals1 vals2)
          (HypJ: forall b1 b2 d, j b1 = Some (b2, d) -> DomS b1 = true /\ DomT b2 = true)
          (R: forall b, REACH m2 (fun b' => isGlobalBlock ge2 b' || getBlocks vals2 b') b = true -> 
                        DomT b = true)
          (PG: meminj_preserves_globals ge1 j)
          (GenvsDomEQ: genvs_domain_eq ge1 ge2)
          (HS: forall b, DomS b = true -> Mem.valid_block m1 b)
          (HT: forall b, DomT b = true -> Mem.valid_block m2 b)
          mu (Hmu: mu = initial_SM DomS DomT
                         (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b)) 
                         (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j),
       (forall b, REACH m1 (fun b' => isGlobalBlock ge1 b' || getBlocks vals1 b') b = true -> 
                  DomS b = true) /\
       SM_wd mu /\ sm_valid mu m1 m2 /\ 
       meminj_preserves_globals ge1 (extern_of mu) /\
       (forall b, isGlobalBlock ge1 b = true -> frgnBlocksSrc mu b = true) /\
       REACH_closed m1 (vis mu) /\
       REACH_closed m1 (mapped (as_inj mu)).
Proof. intros.
  specialize (getBlocks_inject _ _ _ VInj); intros.
  assert (HR: forall b1, REACH m1 (fun b : block => isGlobalBlock ge1 b || getBlocks vals1 b) b1 = true ->
            exists b2 z, j b1 = Some (b2, z) /\
                         REACH m2 (fun b : block => isGlobalBlock ge2 b || getBlocks vals2 b) b2 = true).
         eapply (REACH_inject _ _ _ MInj).
              intros. clear R mu Hmu HS HT.
              apply orb_true_iff in H0.
              destruct H0. 
                rewrite (meminj_preserves_globals_isGlobalBlock _ _ PG _ H0).
                exists b, 0. rewrite <- (genvs_domain_eq_isGlobal _ _ GenvsDomEQ).
                intuition.
              destruct (H _ H0) as [b2 [d [J GB2]]]. exists b2, d; intuition.
  split. intros. 
         destruct (HR _ H0) as [b2 [d [J R2]]].
         apply (HypJ _ _ _ J).
  subst.
  split. eapply initial_SM_wd; try eassumption.
           intros. destruct (HR _ H0) as [b2 [d [J R2]]].
             apply (HypJ _ _ _ J).
  split. split; intros. apply (HS _ H0). apply (HT _ H0). 
  split. eapply meminj_preserves_globals_initSM; intuition.
  split. apply meminj_preserves_globals_init_REACH_frgn; try eassumption.
    intuition.
  split. simpl. apply REACH_is_closed.
  rewrite initial_SM_as_inj. 
    apply (inject_REACH_closed _ _ _ MInj).     
Qed.

(*Proof the match_genv is preserved by callsteps*)
Lemma intern_incr_meminj_preserves_globals: 
      forall {F V} (ge: Genv.t F V) mu
             (PG: meminj_preserves_globals ge (extern_of mu) /\
                  (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true))
             mu' (Inc: intern_incr mu mu'),
      meminj_preserves_globals ge (extern_of mu') /\
      (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu' b = true).
Proof. intros.
  assert (FF: frgnBlocksSrc mu = frgnBlocksSrc mu') by apply Inc.
  rewrite (intern_incr_extern _ _ Inc), FF in PG.
  assumption. 
Qed.

Lemma replace_externs_meminj_preserves_globals:
      forall {F V} (ge: Genv.t F V) nu
          (PG: meminj_preserves_globals ge (extern_of nu) /\
               (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc nu b = true))
          mu  fSrc fTgt (Hyp: mu = replace_externs nu fSrc fTgt)
          (FRG: forall b, frgnBlocksSrc nu b = true -> fSrc b = true),
      meminj_preserves_globals ge (extern_of mu) /\
      (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true).
Proof. intros. destruct PG as [PG FF]; subst.
split.
    rewrite replace_externs_extern.
    apply PG.
intros. destruct nu; simpl in *. 
  apply (FRG _ (FF _ H)). 
Qed.

(*Proof the match_genv is preserved by callsteps*)
Lemma after_external_meminj_preserves_globals: 
      forall {F V} (ge: Genv.t F V) mu (WDmu : SM_wd mu)
             (PG: meminj_preserves_globals ge (extern_of mu) /\
                 (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu b = true))
             nu pubSrc' pubTgt' vals1 m1
             (pubSrcHyp: pubSrc' = fun b => andb (locBlocksSrc mu b)
                                                (REACH m1 (exportedSrc mu vals1) b))

      
             (Hnu: nu = replace_locals mu pubSrc' pubTgt')
             nu' (WDnu' : SM_wd nu') (INC: extern_incr nu nu')  
             m2 (SMV: sm_valid mu m1 m2) (SEP: sm_inject_separated nu nu' m1 m2)
             frgnSrc' ret1 m1'
             (frgnSrcHyp: frgnSrc' = fun b => andb (DomSrc nu' b)
                                                 (andb (negb (locBlocksSrc nu' b)) 
                                                       (REACH m1' (exportedSrc nu' (ret1::nil)) b)))

             frgnTgt' ret2 m2'
             (frgnTgtHyp: frgnTgt' = fun b => andb (DomTgt nu' b)
                                                 (andb (negb (locBlocksTgt nu' b))
                                                       (REACH m2' (exportedTgt nu' (ret2::nil)) b)))

             mu' (Mu'Hyp: mu' = replace_externs nu' frgnSrc' frgnTgt'),
      meminj_preserves_globals ge (extern_of mu') /\
     (forall b, isGlobalBlock ge b = true -> frgnBlocksSrc mu' b = true).
Proof. intros. subst.
destruct PG as [PG FF].
assert (Fincr:= extern_incr_extern _ _ INC).
rewrite replace_locals_extern in Fincr. 
split.
  rewrite replace_externs_extern.
  apply meminj_preserves_genv2blocks.
  apply meminj_preserves_genv2blocks in PG.
  destruct PG as [PGa [PGb PGc]].
  split; intros.
    specialize (PGa _ H). clear PGb PGc. 
    apply (Fincr _ _ _ PGa). 
  split; intros. 
    specialize (PGb _ H). clear PGa PGc.
    apply (Fincr _ _ _ PGb).
  remember (extern_of mu b1) as d.
    destruct d; apply eq_sym in Heqd.
      destruct p. 
      rewrite (Fincr _ _ _ Heqd) in H0.
      inv H0. apply (PGc _ _ _ H Heqd).
    destruct SEP as [SEPa [SEPb SEPc]].
      rewrite replace_locals_as_inj, replace_locals_DomSrc, replace_locals_DomTgt in *. 
      remember (local_of mu b1) as q.
      destruct q; apply eq_sym in Heqq.
        destruct p. destruct INC as [_ [? _]]. 
        rewrite replace_locals_local in H1. rewrite H1 in Heqq.
        destruct (disjoint_extern_local _ WDnu' b1); congruence.
      assert (as_inj mu b1 = None).
        apply joinI_None; assumption.
      destruct (SEPa b1 b2 delta H1 (extern_in_all _ _ _ _ H0)).
      specialize (PGb _ H).
         destruct (extern_DomRng' _ WDmu _ _ _ PGb) as [? [? [? [? [? [? [? ?]]]]]]].
         congruence.
intros. 
  specialize (FF _ H). subst. 
  assert (F': frgnBlocksSrc nu' b = true).
    eapply INC. rewrite replace_locals_frgnBlocksSrc. assumption.
  rewrite replace_externs_frgnBlocksSrc.
  assert (L' := frgnBlocksSrc_locBlocksSrc _ WDnu' _ F').
  unfold DomSrc. 
  rewrite L', (frgnBlocksSrc_extBlocksSrc _ WDnu' _ F'); simpl.
  apply (frgnSrc_shared _ WDnu') in F'.
  apply REACH_nil. unfold exportedSrc. intuition.
Qed.

Definition restrict_sm mu (X:block -> bool) :=
match mu with
  Build_SM_Injection locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern =>
  Build_SM_Injection locBSrc locBTgt pSrc pTgt (restrict local X) 
                     extBSrc extBTgt fSrc fTgt (restrict extern X)
end.

Lemma restrict_sm_com: forall mu X Y,
      restrict_sm (restrict_sm mu X) Y = restrict_sm (restrict_sm mu Y) X.
Proof. intros. unfold restrict_sm.
  destruct mu.
  f_equal; apply restrict_com.
Qed.

Lemma restrict_sm_nest: forall mu X Y 
         (HXY: forall b, Y b = true -> X b = true),
      restrict_sm (restrict_sm mu X) Y = restrict_sm mu Y.
Proof. intros. unfold restrict_sm.
  destruct mu; simpl in *.
  f_equal; apply restrict_nest; assumption.
Qed.

Lemma restrict_sm_nest': forall mu X Y 
         (HXY: forall b, Y b = true -> X b = true),
      restrict_sm (restrict_sm mu Y) X = restrict_sm mu Y.
Proof. intros. rewrite restrict_sm_com.
  apply restrict_sm_nest; assumption. 
Qed.

Lemma restrict_sm_local: forall mu X, 
      local_of (restrict_sm mu X) = restrict (local_of mu) X.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_pub: forall mu X, 
      pub_of (restrict_sm mu X) = restrict (pub_of mu) X.
Proof. intros. unfold pub_of. 
       extensionality b. destruct mu; simpl.
       unfold restrict.
       remember (pubBlocksSrc b) as d.
       destruct d; trivial.
       destruct (X b); trivial.
Qed.

Lemma restrict_sm_extern: forall mu X, 
      extern_of (restrict_sm mu X) = restrict (extern_of mu) X.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_foreign: forall mu X, 
      foreign_of (restrict_sm mu X) = restrict (foreign_of mu) X.
Proof. intros. unfold foreign_of. 
       extensionality b. destruct mu; simpl.
       unfold restrict.
       remember (frgnBlocksSrc b) as d.
       destruct d; trivial.
       destruct (X b); trivial.
Qed.

Lemma restrict_sm_all: forall mu X,
       as_inj (restrict_sm mu X) = restrict (as_inj mu) X.
Proof. intros. unfold as_inj.
   rewrite restrict_sm_local, restrict_sm_extern.
   apply join_restrict. 
Qed.

Lemma restrict_sm_local': forall mu (WD: SM_wd mu) X
      (HX: forall b, vis mu b = true -> X b = true), 
      local_of (restrict_sm mu X) = local_of mu.
Proof. intros. rewrite restrict_sm_local.
 apply restrict_outside. intros.
 apply HX.
 destruct (local_DomRng _ WD _ _ _ H). unfold vis. intuition.
Qed.

Lemma restrict_sm_pub': forall mu (WD: SM_wd mu) X
      (HX: forall b, vis mu b = true ->
                     X b = true), 
      pub_of (restrict_sm mu X) = pub_of mu.
Proof. intros. rewrite restrict_sm_pub.
 apply restrict_outside. intros.
 apply HX. apply pub_in_local in H. 
 destruct (local_DomRng _ WD _ _ _ H). unfold vis. intuition.
Qed. 

Lemma restrict_sm_foreign': forall mu (WD: SM_wd mu) X
      (HX: forall b, vis mu b = true -> X b = true), 
      foreign_of (restrict_sm mu X) = foreign_of mu.
Proof. intros. rewrite restrict_sm_foreign.
 apply restrict_outside. intros.
 apply HX. unfold vis. rewrite orb_true_iff.
 right. eapply (foreign_DomRng _ WD _ _ _ H).
Qed. 

Lemma restrict_sm_locBlocksSrc: forall mu X, 
      locBlocksSrc (restrict_sm mu X) = locBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_extBlocksSrc: forall mu X, 
      extBlocksSrc (restrict_sm mu X) = extBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_pubBlocksSrc: forall mu X, 
      pubBlocksSrc (restrict_sm mu X) = pubBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_frgnBlocksSrc: forall mu X, 
      frgnBlocksSrc (restrict_sm mu X) = frgnBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_DomSrc: forall mu X, 
      DomSrc (restrict_sm mu X) = DomSrc mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_DOM: forall mu X, 
      DOM (restrict_sm mu X) = DOM mu.
Proof. intros. destruct mu; reflexivity. Qed.

Lemma restrict_sm_locBlocksTgt: forall mu X, 
      locBlocksTgt (restrict_sm mu X) = locBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_extBlocksTgt: forall mu X, 
      extBlocksTgt (restrict_sm mu X) = extBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_pubBlocksTgt: forall mu X, 
      pubBlocksTgt (restrict_sm mu X) = pubBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_frgnBlocksTgt: forall mu X, 
      frgnBlocksTgt (restrict_sm mu X) = frgnBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_DomTgt: forall mu X, 
      DomTgt (restrict_sm mu X) = DomTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.
Lemma restrict_sm_RNG: forall mu X, 
      RNG (restrict_sm mu X) = RNG mu.
Proof. intros. destruct mu; reflexivity. Qed.

Lemma restrict_sm_WD:
      forall mu (WD: SM_wd mu) X
          (HX: forall b, vis mu b = true -> X b = true),
      SM_wd (restrict_sm mu X).
Proof. intros.
split; intros.
  rewrite restrict_sm_locBlocksSrc, restrict_sm_extBlocksSrc.
    apply WD.
  rewrite restrict_sm_locBlocksTgt, restrict_sm_extBlocksTgt.
    apply WD.
  rewrite restrict_sm_locBlocksSrc, restrict_sm_locBlocksTgt.
    rewrite restrict_sm_local in H.
    eapply WD. eapply restrictD_Some. apply H.
  rewrite restrict_sm_extBlocksSrc, restrict_sm_extBlocksTgt.
    rewrite restrict_sm_extern in H.
    eapply WD. eapply restrictD_Some. apply H.
  rewrite restrict_sm_pubBlocksSrc in H. 
    destruct (pubSrc _ WD _ H) as [b2 [d1 [PUB1 PT2]]].
    rewrite restrict_sm_pubBlocksTgt. 
    exists b2, d1. 
    rewrite restrict_sm_pub'; intuition.
  rewrite restrict_sm_frgnBlocksSrc in H. 
    destruct (frgnSrc _ WD _ H) as [b2 [d1 [FRG1 FT2]]].
    rewrite restrict_sm_frgnBlocksTgt. 
    exists b2, d1. 
    rewrite restrict_sm_foreign'; intuition.
  rewrite restrict_sm_locBlocksTgt. 
    rewrite restrict_sm_pubBlocksTgt in H.
    apply (pubBlocksLocalTgt _ WD _ H).
  rewrite restrict_sm_extBlocksTgt. 
    rewrite restrict_sm_frgnBlocksTgt in H.
    apply (frgnBlocksExternTgt _ WD _ H).
Qed.


Lemma restrict_sm_preserves_globals: forall {F V} (ge:Genv.t F V) mu X
  (PG : meminj_preserves_globals ge (as_inj mu))
  (Glob : forall b, isGlobalBlock ge b = true -> X b = true),
meminj_preserves_globals ge (as_inj (restrict_sm mu X)).
Proof. intros. rewrite restrict_sm_all.
  eapply restrict_preserves_globals; assumption.
Qed.

Module SM_simulation. Section SharedMemory_simulation_inject. 
  Context {F1 V1 C1 F2 V2 C2:Type}
          (Sem1 : @EffectSem (Genv.t F1 V1) C1)
          (Sem2 : @EffectSem (Genv.t F2 V2) C2)
          (ge1: Genv.t F1 V1)
          (ge2: Genv.t F2 V2)
          (entry_points : list (val * val * signature)).

  Record SM_simulation_inject := 
  { core_data : Type;
    match_state : core_data -> SM_Injection -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    match_sm_wd: forall d mu c1 m1 c2 m2, 
          match_state d mu c1 m1 c2 m2 ->
          SM_wd mu;

    genvs_dom_eq: genvs_domain_eq ge1 ge2;

(*
    match_genv: forall d mu c1 m1 c2 m2,  match_state d mu c1 m1 c2 m2 -> 
          meminj_preserves_globals ge1 (foreign_of mu); 
    The following formulation using extern_of is slightly stronger, since it requires
    that the third condition of mem-inj_preserves_globals be satisfied
    for all of extern_of, bit just foreign_of, so is preserved by
    extern_incr and the adaptation of frgSrc by replaces_externs in 
    rule afterExternal. It is also equivalent to a formulation that
    uses as_inj instead of extern_of; see 
    Lemma match_genv_meminj_preserves_extern_iff_all in effect_properties.v*)
    match_genv: forall d mu c1 m1 c2 m2 (MC:match_state d mu c1 m1 c2 m2),
          meminj_preserves_globals ge1 (extern_of mu) /\
          (forall b, isGlobalBlock ge1 b = true -> frgnBlocksSrc mu b = true); 

    match_visible: forall d mu c1 m1 c2 m2, 
          match_state d mu c1 m1 c2 m2 -> 
          REACH_closed m1 (vis mu);

    match_restrict: forall d mu c1 m1 c2 m2 X, 
          match_state d mu c1 m1 c2 m2 -> 
          (forall b, vis mu b = true -> X b = true) ->
          REACH_closed m1 X ->
          match_state d (restrict_sm mu X) c1 m1 c2 m2;

    match_validblocks: forall d mu c1 m1 c2 m2, 
          match_state d mu c1 m1 c2 m2 ->
          sm_valid mu m1 m2;               

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2 DomS DomT,
          initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          Forall2 (val_inject j) vals1 vals2 ->
          meminj_preserves_globals ge1 j ->

        (*the next two conditions are required to guarantee intialSM_wd*)
         (forall b1 b2 d, j b1 = Some (b2, d) -> 
                          DomS b1 = true /\ DomT b2 = true) ->
         (forall b, REACH m2 (fun b' => isGlobalBlock ge2 b' || getBlocks vals2 b') b = true -> DomT b = true) ->

        (*the next two conditions ensure the initialSM satisfies sm_valid*)
         (forall b, DomS b = true -> Mem.valid_block m1 b) ->
         (forall b, DomT b = true -> Mem.valid_block m2 b) ->

       exists cd, exists c2, 
            initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            (*Lemma StructuredInjections.initial_SM_as_inj implies 
              that Mem.inject (initial_SM DomS
                                       DomT 
                                       (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b)) 
                                       (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j)
                              m1 m2 holds*)
            match_state cd (initial_SM DomS
                                       DomT 
                                       (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b)) 
                                       (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j)
                           c1 m1 c2 m2;

    core_diagram : 
      forall st1 m1 st1' m1', 
        corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 mu m2,
        match_state cd mu st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists mu',
          intern_incr mu mu' /\
          sm_inject_separated mu mu' m1 m2 /\

          (*new condition: corestep evolution is soundly and completely 
                           tracked by the local knowledge*)
          sm_locally_allocated mu mu' m1 m2 m1' m2' /\ 
          match_state cd' mu' st1' m1' st2' m2' /\

          (*formally, the following 2 conditions already follow
            from match_state_wd and match_state_sm_valid, but we
            temporarily duplicate them here in order to check that 
            the constructions in the transitivity proof are ok:*)
          SM_wd mu' /\ sm_valid mu' m1' m2' /\

          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd)

        (*One would suspect that we could add the following confinement guarantees
          to this rule:
          /\ Mem.unchanged_on (fun b2 ofs => extBlocksTgt mu b2 = true /\
                                 ~ exists b1 d, foreign_of mu b1=Some (b2,d)) m2 m2' 
          /\ forall b ofs, Mem.unchanged_on (fun b' ofs' => b'=b /\ ofs'=ofs) m1 m1' ->
              forall b2 d, foreign_of mu b = Some(b2,d) -> 
                           Mem.unchanged_on (fun b' ofs' => b'=b2 /\ ofs'=ofs+d) m2 m2'
         Indeed, as RGTgt_multicoreNOEFFECTS at the end of this file shows, these
         guarantees suffice for establishing the afterEtxernal-rely (under the mild
         axiom DECIBILITYAXIOM). However, these guarantees cannot be pushed through
         the transitivity proof (inductive step of "case1"), since Mem_unchanged_on does not decompose, ie for
            step m m' /\ step m' m'' /\ UnchOn P m m'' does not imply
           UnchOn P m m' /\ UnchOn P m' m''. But such decomposition would be needed
           to apply the induction hypotheses of core_diagram in file effect_corediagram_trans.v
          The advantage of/reason for using effects is to have such decomposition, as
            step m m' /\ step m' m'' /\ Estep E m m'' does imply 
            Estep E m m' /\ Estep E m' m''.*);

    effcore_diagram : 
      forall st1 m1 st1' m1' U1, 
        effstep Sem1 ge1 U1 st1 m1 st1' m1' ->

      forall cd st2 mu m2,
        match_state cd mu st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists mu',
          intern_incr mu mu' /\
          sm_inject_separated mu mu' m1 m2 /\

          (*new condition: corestep evolution is soundly and completely 
                           tracked by the local knowledge*)
          sm_locally_allocated mu mu' m1 m2 m1' m2' /\ 

          match_state cd' mu' st1' m1' st2' m2' /\

          (*could add the following 2 assertions here, too, but 
             we checked already that they're satisfied in the previous
             clause SM_wd mu' /\ sm_valid mu' m1' m2' /\*)

          exists U2,              
            ((effstep_plus Sem2 ge2 U2 st2 m2 st2' m2' \/
              (effstep_star Sem2 ge2 U2 st2 m2 st2' m2' /\
               core_ord cd' cd)) /\ 

             forall b ofs, U2 b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           Mem.valid_block m1 b1 /\ U1 b1 (ofs-delta1) = true)));

    (*additionally requires U1 to be disjoint from unknown etc, in UHyp*)
    effcore_diagram_strong : 
      forall st1 m1 st1' m1' U1, 
        effstep Sem1 ge1 U1 st1 m1 st1' m1' ->

      forall cd st2 mu m2
        (UHyp: forall b1 z, U1 b1 z = true -> vis mu b1 = true),
        match_state cd mu st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists mu',
          intern_incr mu mu' /\
          sm_inject_separated mu mu' m1 m2 /\

          (*new condition: corestep evolution is soundly and completely 
                           tracked by the local knowledge*)
          sm_locally_allocated mu mu' m1 m2 m1' m2' /\ 

          match_state cd' mu' st1' m1' st2' m2' /\

          (*could add the following 2 assertions here, too, but 
             we checked already that they're satisfied in the previous
             clause SM_wd mu' /\ sm_valid mu' m1' m2' /\*)

          exists U2,              
            ((effstep_plus Sem2 ge2 U2 st2 m2 st2' m2' \/
              (effstep_star Sem2 ge2 U2 st2 m2 st2' m2' /\
               core_ord cd' cd)) /\

             forall b ofs, U2 b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           U1 b1 (ofs-delta1) = true)));

      effcore_diagram_strong_perm : 
      forall st1 m1 st1' m1' U1, 
        effstep Sem1 ge1 U1 st1 m1 st1' m1' ->

      forall cd st2 mu m2
        (UHyp: forall b1 z, U1 b1 z = true -> Mem.valid_block m1 b1 ->
                            vis mu b1 = true),
        match_state cd mu st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists mu',
          intern_incr mu mu' /\
          sm_inject_separated mu mu' m1 m2 /\

          (*new condition: corestep evolution is soundly and completely 
                           tracked by the local knowledge*)
          sm_locally_allocated mu mu' m1 m2 m1' m2' /\ 

          match_state cd' mu' st1' m1' st2' m2' /\

          (*could add the following 2 assertions here, too, but 
             we checked already that they're satisfied in the previous
             clause SM_wd mu' /\ sm_valid mu' m1' m2' /\*)

          exists U2,              
            ((effstep_plus Sem2 ge2 U2 st2 m2 st2' m2' \/
              (effstep_star Sem2 ge2 U2 st2 m2 st2' m2' /\
               core_ord cd' cd)) /\

             forall b ofs, U2 b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           U1 b1 (ofs-delta1) = true /\ 
                           Mem.perm m1 b1 (ofs-delta1) Max Nonempty)));

    core_halted : forall cd mu c1 m1 c2 m2 v1,
      match_state cd mu c1 m1 c2 m2 ->
      halted Sem1 c1 = Some v1 ->

      exists v2, 
             Mem.inject (as_inj mu) m1 m2 /\
             val_inject (as_inj mu) v1 v2 /\
             halted Sem2 c2 = Some v2;

    core_at_external : 
      forall cd mu c1 m1 c2 m2 e vals1 ef_sig,
        match_state cd mu c1 m1 c2 m2 ->
        at_external Sem1 c1 = Some (e,ef_sig,vals1) ->
        ( Mem.inject (as_inj mu) m1 m2 /\ 

         exists vals2, 
            Forall2 (val_inject (as_inj mu)) vals1 vals2 /\ 
            at_external Sem2 c2 = Some (e,ef_sig,vals2)); 
          (*Like in coreHalted, one might consider a variant that
             asserts Mem.inject m1 m2 and val_inject vals1 vals2
             w.r.t. shared_of mu instead of as_inj mu.
            Again this might be possible, but probably only at the price of
               pushing such an invariant through corediagram etc.*)

    eff_after_external: 
      forall cd mu st1 st2 m1 e vals1 m2 ef_sig vals2 e' ef_sig'
        (*standard assumptions:*)
        (MemInjMu: Mem.inject (as_inj mu) m1 m2)
        (MatchMu: match_state cd mu st1 m1 st2 m2)
        (AtExtSrc: at_external Sem1 st1 = Some (e,ef_sig,vals1))

        (*We include the clause AtExtTgt to ensure that vals2 is 
         uniquely determined. We have e=e' and ef_sig=ef_sig' by the
         at_external clause, but omitting the hypothesis AtExtTgt would
         result in in 2 not necesssarily equal target argument lists
         in language 3 in the transitivity, as val_inject is not functional
         (in the case where the left value is Vundef) *)
        (AtExtTgt: at_external Sem2 st2 = Some (e',ef_sig',vals2)) 

        (ValInjMu: Forall2 (val_inject (as_inj mu)) vals1 vals2)  

        (*Lemma eff_atexternal_check in effect_properties.v shows that 
            global blocks from ge1 are in REACH m1 (exportedSrc mu vals1 and
            global blocks from ge1 are in REACH m2 (exportedTgt mu vals2*)
        pubSrc' (pubSrcHyp: pubSrc' = fun b => andb (locBlocksSrc mu b)
                                                    (REACH m1 (exportedSrc mu vals1) b))

        pubTgt' (pubTgtHyp: pubTgt' = fun b => andb (locBlocksTgt mu b)
                                                    (REACH m2 (exportedTgt mu vals2) b))

        nu (NuHyp: nu = replace_locals mu pubSrc' pubTgt'),

      (*Lemma eff_after_check1 in in effect_properties.v shows that 
                 SM_wd nu /\ sm_valid nu m1 m2 /\
                 Mem.inject (as_inj nu) m1 m2 /\
                 Forall2 (val_inject (as_inj nu)) vals1 vals2 holds*)

      forall nu' ret1 m1' ret2 m2'
        (INC: extern_incr nu nu')  
        (SEP: sm_inject_separated nu nu' m1 m2)

        (WDnu': SM_wd nu') (SMvalNu': sm_valid nu' m1' m2')

        (MemInjNu': Mem.inject (as_inj nu') m1' m2')
        (RValInjNu': val_inject (as_inj nu') ret1 ret2)

        (FwdSrc: mem_forward m1 m1') (FwdTgt: mem_forward m2 m2')

        frgnSrc' (frgnSrcHyp: frgnSrc' = fun b => andb (DomSrc nu' b)
                                                 (andb (negb (locBlocksSrc nu' b)) 
                                                       (REACH m1' (exportedSrc nu' (ret1::nil)) b)))

        frgnTgt' (frgnTgtHyp: frgnTgt' = fun b => andb (DomTgt nu' b)
                                                 (andb (negb (locBlocksTgt nu' b))
                                                       (REACH m2' (exportedTgt nu' (ret2::nil)) b)))

        mu' (Mu'Hyp: mu' = replace_externs nu' frgnSrc' frgnTgt')

        (*follows, as proven by Lemma eff_after_check2:
             SM_wd mu' /\ sm_valid mu' m1' m2' /\*)
        (*follows, as proven by Lemma eff_after_check3:
             Mem.inject (as_inj mu') m1' m2' /\ val_inject (as_inj mu') ret1 ret2*)

        (*follows, as proven by Lemma eff_after_check4: 
             inject_incr (as_inj mu) (as_inj mu')*)
        (*follows, as proven by Lemma eff_after_check5:
             sm_inject_separated mu mu' m1 m2 /\*)
 
         (UnchPrivSrc: Mem.unchanged_on (fun b ofs => locBlocksSrc nu b = true /\ 
                                                      pubBlocksSrc nu b = false) m1 m1') 

         (UnchLOOR: Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'),
        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' mu' st1' m1' st2' m2'
}.

(*End SharedMemory_simulation_inject. *)

(*End SM_simulation.*)

(*The following lemma shows that the incoming memories are injected not only
by initial_SM, but by locvisible(initial_SM). Lemma halted_loc_check 
is the counterpart of this. *)
Lemma initial_locvisible: forall (I:SM_simulation_inject) v1 v2 sig,
  In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2 DomS DomT,
          initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          Forall2 (val_inject j) vals1 vals2 ->
          meminj_preserves_globals ge1 j ->

        (*the next two conditions are required to guarantee intialSM_wd*)
         (forall b1 b2 d, j b1 = Some (b2, d) -> 
                          DomS b1 = true /\ DomT b2 = true) ->
         (forall b, REACH m2 (fun b' => isGlobalBlock ge2 b' || getBlocks vals2 b') b = true -> DomT b = true) ->

        (*the next two conditions ensure the initialSM satisfies sm_valid*)
         (forall b, DomS b = true -> Mem.valid_block m1 b) ->
         (forall b, DomT b = true -> Mem.valid_block m2 b) ->

       exists cd, exists c2, 
            initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state I cd (initial_SM DomS
                                       DomT 
                                       (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b))
                                       (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j)
                           c1 m1 c2 m2 /\
           Mem.inject (locvisible_of (initial_SM DomS
                                       DomT 
                                       (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b)) 
                                       (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j)) m1 m2.
Proof. intros.
  destruct (core_initial I _ _ _ H _ _ _ _ _ _ _ _ H0 H1 H2 H3 H4 H5 H6 H7)
    as [cd [c2 [IC MS]]].
  clear H6 H7.
  exists cd, c2.
  split; trivial.
  split. trivial.
  specialize (match_validblocks I _ _ _ _ _ _ MS). intros VB.
  unfold locvisible_of. simpl.
  split; intros.
    split; intros.
       apply joinD_Some in H6. 
       destruct H6; simpl.
       remember (REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                             getBlocks vals1 b) b1).
       destruct b; try inv H6.
         solve [eapply H1; eassumption].
       destruct H6; discriminate. 
    apply joinD_Some in H6. 
       destruct H6; simpl.
       remember (REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                             getBlocks vals1 b) b1).
       destruct b; try inv H6.
         solve [eapply H1; eassumption].
       destruct H6; discriminate.
    apply joinD_Some in H6. 
       destruct H6; simpl.
       remember (REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                             getBlocks vals1 b) b1).
       destruct b; try inv H6.
         specialize (Mem.mi_memval  _ _ _ (Mem.mi_inj _ _ _ H1) _ _ _ _ H9 H7).
         intros. inv H6; try econstructor.
           apply joinI. left. 
           assert (R: REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                             getBlocks vals1 b) b0 = true).
             apply REACHAX. apply eq_sym in Heqb. apply REACHAX in Heqb.
             destruct Heqb as [L HL].
             eexists. eapply reach_cons. apply HL. apply H7. rewrite <- H8. reflexivity.
           rewrite R. eassumption.
           trivial.
       destruct H6; discriminate.

    unfold join. 
      remember (REACH m1 (fun b' : block => isGlobalBlock ge1 b' || 
                                            getBlocks vals1 b') b).
      destruct b0; trivial.
      remember (j b). destruct o; trivial. destruct p; apply eq_sym in Heqo.
       exfalso. apply H6. eapply VB. apply (H4 _ _ _ Heqo).
    apply joinD_Some in H6. 
       destruct H6; simpl.
       remember (REACH m1 (fun b' : block => isGlobalBlock ge1 b' || 
                                             getBlocks vals1 b') b).
       destruct b0; try inv H6. eapply VB. apply (H4 _ _ _ H8).
       destruct H6; discriminate.

   intros b1; intros. 
    apply joinD_Some in H7. 
      destruct H7; simpl.
      remember (REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                            getBlocks vals1 b) b1).
       destruct b; try inv H7.
       apply joinD_Some in H8. 
         destruct H8; simpl.
         remember (REACH m1 (fun b : block => isGlobalBlock ge1 b || 
                                              getBlocks vals1 b) b2).
          destruct b; try inv H7.
          eapply H1; eassumption.
       destruct H7; discriminate. 
     destruct H7; discriminate.

     apply joinD_Some in H6. 
       destruct H6; simpl.
       remember (REACH m1 (fun b' : block => isGlobalBlock ge1 b' || 
                                             getBlocks vals1 b') b).
       destruct b0; try inv H6.
         eapply H1; eassumption.
       destruct H6; discriminate.
Qed.

End SharedMemory_simulation_inject. 

End SM_simulation.

Definition FLIP mu := 
  match mu with
    Build_SM_Injection locBSrc locBTgt pSrc pTgt local extBSrc extBTgt fSrc fTgt extern =>
    Build_SM_Injection extBSrc extBTgt fSrc fTgt extern locBSrc locBTgt pSrc pTgt local 
  end.

Lemma SAWP_wd: forall mu (WD: SM_wd mu), SM_wd (FLIP mu).
intros.
destruct mu; simpl in *.
destruct WD.
split; intros; simpl in *; try solve[auto]. 
  destruct (disjoint_extern_local_Src b); intuition.
  destruct (disjoint_extern_local_Tgt b); intuition.
  apply (extern_DomRng _ _ _ H). 
  apply (local_DomRng _ _ _ H).
Qed.

Lemma FLIPlocBlocksSrc: forall mu,
  locBlocksSrc (FLIP mu) = extBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPlocBlocksTgt: forall mu,
  locBlocksTgt (FLIP mu) = extBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.

Lemma FLIPextBlocksSrc: forall mu,
  extBlocksSrc (FLIP mu) = locBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPextBlocksTgt: forall mu,
  extBlocksTgt (FLIP mu) = locBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.

Lemma FLIPpubBlocksSrc: forall mu,
  pubBlocksSrc (FLIP mu) = frgnBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPpubBlocksTgt: forall mu,
  pubBlocksTgt (FLIP mu) = frgnBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed.

Lemma FLIPfrgnBlocksSrc: forall mu,
  frgnBlocksSrc (FLIP mu) = pubBlocksSrc mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPfrgnBlocksTgt: forall mu,
  frgnBlocksTgt (FLIP mu) = pubBlocksTgt mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPlocal: forall mu,
  local_of (FLIP mu) = extern_of mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma FLIPextern: forall mu,
  extern_of (FLIP mu) = local_of mu.
Proof. intros. destruct mu; reflexivity. Qed. 

Lemma RelyGuaranteeSrc: forall mu (WD: SM_wd mu) Esrc m m'
              (SrcHyp: forall b ofs, Esrc b ofs = true -> 
                                     vis mu b = true)
               (Unch: Mem.unchanged_on (fun b z => Esrc b z = false) m m'),
         Mem.unchanged_on (fun b ofs => locBlocksSrc (FLIP mu) b = true /\ 
                                        pubBlocksSrc (FLIP mu) b = false) m m'.
Proof. intros.
  eapply mem_unchanged_on_sub; try eassumption.
  intros. simpl.
  rewrite FLIPlocBlocksSrc, FLIPpubBlocksSrc in H.
  case_eq (Esrc b ofs); intros; trivial; simpl in *.
  destruct H.
  destruct (disjoint_extern_local_Src _ WD b). 
  apply SrcHyp in H0. unfold vis in H0. rewrite H2, H1 in H0. discriminate. 
  congruence.
Qed.

Lemma unchanged_on_perm: forall (P:block -> Z -> Prop) m m'
      (Unch: Mem.unchanged_on P m m'),
      Mem.unchanged_on (fun b z => P b z /\ Mem.perm m b z Max Nonempty) m m'.
Proof. intros.
split; intros; eapply Unch; eauto.
apply H. apply H.
Qed.

Lemma unchanged_on_perm': forall (P:block -> Z -> Prop) m m'
      (Unch: Mem.unchanged_on (fun b z => P b z \/ ~ Mem.perm m b z Max Nonempty) m m'),
      Mem.unchanged_on P m m'.
Proof. intros.
split; intros; eapply Unch; eauto.
Qed. 

Lemma RelyGuaranteeTgtPerm: forall mu Etgt Esrc m2 m2' (WD: SM_wd mu) m1
            (TgtHyp: forall b ofs, Etgt b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           Esrc b1 (ofs-delta1) = true /\ Mem.perm m1 b1 (ofs-delta1) Max Nonempty)))
            (Unch2: Mem.unchanged_on (fun b z => Etgt b z = false) m2 m2')
            (SrcHyp: forall b ofs, Esrc b ofs = true -> vis mu b = true)
            (*m1 (SrcPerm: forall b1 z, Esrc b1 z = true -> Mem.perm m1 b1 z Max Nonempty)*),
            Mem.unchanged_on (local_out_of_reach (FLIP mu) m1) m2 m2'.
Proof. intros.
  eapply mem_unchanged_on_sub; try eassumption; clear Unch2.
  intros. simpl.
  case_eq (Etgt b ofs); intros; trivial.
  destruct (TgtHyp _ _ H0) as [VB2 F]; clear TgtHyp.
  destruct H.
  rewrite FLIPlocBlocksTgt in H. 
  destruct F as [b1 [d1 [Frg [ES P]]]].
    apply (extBlocksTgt_locBlocksTgt _ WD _ H).
  destruct (H1 b1 d1); clear H1.
     rewrite FLIPlocal.
     apply foreign_in_extern; assumption.
     congruence. 
  rewrite FLIPpubBlocksSrc in H2.
    apply (foreign_DomRng _ WD) in Frg. intuition.
    rewrite H6 in H2. inv H2.
Qed.

Lemma RelyGuaranteeTgt: forall mu Etgt Esrc m2 m2' (WD: SM_wd mu)
            (TgtHyp: forall b ofs, Etgt b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           Esrc b1 (ofs-delta1) = true)))
            (Unch2: Mem.unchanged_on (fun b z => Etgt b z = false) m2 m2')
            (SrcHyp: forall b ofs, Esrc b ofs = true -> vis mu b = true)
            m1 (SrcPerm: forall b1 z, Esrc b1 z = true -> Mem.perm m1 b1 z Max Nonempty),
            Mem.unchanged_on (local_out_of_reach (FLIP mu) m1) m2 m2'.
Proof. intros. 
  eapply mem_unchanged_on_sub; try eassumption; clear Unch2.
  intros. simpl. rename b into b2.
  case_eq (Etgt b2 ofs); intros; trivial.
  destruct (TgtHyp _ _ H0) as [VB2 F]; clear TgtHyp.
  destruct H.
  rewrite FLIPlocBlocksTgt in H.
  destruct F as [b1 [d1 [Frg ES]]].
    apply (extBlocksTgt_locBlocksTgt _ WD _ H).
  rewrite FLIPlocal in H1.
  destruct (foreign_DomRng _ WD _ _ _ Frg) as [AA [BB [CC [DD [EE [FF [GG HH]]]]]]].
(*  apply SrcHyp in ES. unfold vis in ES.
    rewrite CC in ES; simpl in ES.(* rewrite H2 in *. inv CC.*)*)
  specialize (SrcPerm _ _ ES).
  destruct (H1 b1 d1); clear H1.
     apply foreign_in_extern; assumption.
     contradiction.
  rewrite FLIPpubBlocksSrc in H2. congruence. 
Qed.

(*Once these RG results are used in a linker/concurrency machine,
  we will need to remove all blocks b with isGlobalBlock ge from pubBlocks*)
Lemma RGSrc_multicore: forall mu Esrc m m'
         (SrcHyp: forall b ofs, Esrc b ofs = true -> vis mu b = true)
         (Unch: Mem.unchanged_on (fun b z => Esrc b z = false) m m')
          nu, 
         (forall b, locBlocksSrc nu b = true -> locBlocksSrc mu b = false) ->
         (forall b, pubBlocksSrc nu b = true <-> 
                   (frgnBlocksSrc mu b && locBlocksSrc nu b) = true) ->
         (*This hypothesis is not needed (GS):
           (forall b1 b2 d, pub_of nu b1 = Some(b2, d) 
           -> foreign_of mu b1 = Some(b2,d)) ->*)
         Mem.unchanged_on (fun b ofs => locBlocksSrc nu b = true /\ 
                                        pubBlocksSrc nu b = false) m m'.
Proof. intros.
  assert (H1: True). refine I.
  eapply mem_unchanged_on_sub; try eassumption.
  intros b ofs H2. simpl.
  destruct H2. rename b into b1. specialize (H _ H2). 
  case_eq (Esrc b1 ofs); intros; trivial; simpl in *.
  apply SrcHyp in H4. unfold vis in H4. rewrite H in H4. simpl in H4.  
  clear Unch SrcHyp.
  destruct (H0 b1) as [_ ?].
    rewrite H4, H2 in H5. simpl in H5.
    rewrite H5 in H3; intuition.
Qed.

Lemma RGTgt_multicore: forall mu Etgt Esrc m2 m2' (WD: SM_wd mu)
            (TgtHyp: forall b ofs, Etgt b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           Esrc b1 (ofs-delta1) = true)))
            (Unch2: Mem.unchanged_on (fun b z => Etgt b z = false) m2 m2')
            (*(SrcHyp: forall b ofs, Esrc b ofs = true -> vis mu b = true)*)
            m1 (SrcPerm: forall b1 z, Esrc b1 z = true -> Mem.perm m1 b1 z Max Nonempty)
            nu
         (X1: forall b, locBlocksTgt nu b = true -> locBlocksTgt mu b = false)
         (X2: forall b1 b2 d, foreign_of mu b1 = Some(b2, d) -> 
                              locBlocksSrc nu b1 || locBlocksTgt nu b2 = true ->
                              pub_of nu b1 = Some(b2,d)),
            Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'.
Proof. intros.
  eapply mem_unchanged_on_sub; try eassumption; clear Unch2.
  intros. simpl. rename b into b2.
  case_eq (Etgt b2 ofs); intros; trivial.
  destruct (TgtHyp _ _ H0) as [VB2 F]; clear TgtHyp.
  destruct H.
  specialize (X1 _ H). 
  destruct (F X1) as [b1 [d1 [Frg ES]]]; clear F.
  destruct (foreign_DomRng _ WD _ _ _ Frg) as [AA [BB [CC [DD [EE [FF [GG HH]]]]]]].
  clear DD.
(*  apply SrcHyp in ES. clear SrcHyp.
    rewrite H2 in *. inv CC.
  clear H2.*)
  specialize (X2 _ _ _ Frg). rewrite H in X2.
  rewrite orb_true_r in X2. specialize (X2 (eq_refl _)). 
  destruct (H1 b1 d1).
    apply pub_in_local. apply X2.
    specialize (SrcPerm _ _ ES). contradiction.
  rewrite (pubSrcContra _ _ H2) in X2. inv X2. 
Qed.

Lemma RGTgt_multicorePerm: forall mu Etgt Esrc m2 m2' (WD: SM_wd mu) m1
            (TgtHyp: forall b ofs, Etgt b ofs = true -> 
                       (Mem.valid_block m2 b /\
                         (locBlocksTgt mu b = false ->
                           exists b1 delta1, foreign_of mu b1 = Some(b,delta1) /\
                           Esrc b1 (ofs-delta1) = true /\ Mem.perm m1 b1 (ofs-delta1) Max Nonempty)))
            (Unch2: Mem.unchanged_on (fun b z => Etgt b z = false) m2 m2')
            (*(SrcHyp: forall b ofs, Esrc b ofs = true -> vis mu b = true)*)
            nu
         (X1: forall b, locBlocksTgt nu b = true -> locBlocksTgt mu b = false)
         (X2: forall b1 b2 d, foreign_of mu b1 = Some(b2, d) -> 
                              locBlocksSrc nu b1 || locBlocksTgt nu b2 = true ->
                              pub_of nu b1 = Some(b2,d)),
            Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'.
Proof. intros.
  eapply mem_unchanged_on_sub; try eassumption; clear Unch2.
  intros. simpl. rename b into b2.
  case_eq (Etgt b2 ofs); intros; trivial.
  destruct (TgtHyp _ _ H0) as [VB2 F]; clear TgtHyp.
  destruct H.
  specialize (X1 _ H). 
  destruct (F X1) as [b1 [d1 [Frg [ES P]]]]; clear F.
  destruct (foreign_DomRng _ WD _ _ _ Frg) as [AA [BB [CC [DD [EE [FF [GG HH]]]]]]].
  clear DD.
  (*destruct (SrcHyp _ _ ES); clear SrcHyp.
    rewrite H2 in *. inv CC.
  clear H2.*)
  specialize (X2 _ _ _ Frg). rewrite H in X2.
  rewrite orb_true_r in X2. specialize (X2 (eq_refl _)). 
  destruct (H1 b1 d1).
    apply pub_in_local. apply X2.
    contradiction.
  rewrite (pubSrcContra _ _ H2) in X2. inv X2. 
Qed.

Lemma Fwd_unch: forall m m' (FWD: mem_forward m m')
           b ofs (P: ~ Mem.perm m b ofs Max Nonempty),
     Mem.unchanged_on (fun b' ofs' => b' = b /\ ofs' = ofs) m m'.
Proof. intros.
split; intros. 
  destruct H; subst. 
  split; intros; elim P. eapply Mem.perm_max. eapply Mem.perm_implies; try eassumption. apply perm_any_N. 
      eapply FWD. assumption. eapply Mem.perm_max. eapply Mem.perm_implies; try eassumption. apply perm_any_N.
destruct H; subst. 
  elim P. eapply Mem.perm_max. eapply Mem.perm_implies; try eassumption. apply perm_any_N.
Qed.

Lemma unchanged_on_union:
      forall m m' P Q (HP: Mem.unchanged_on P m m') (HQ: Mem.unchanged_on Q m m')
             (PQ: block -> Z -> Prop) (HPQ: forall b ofs, PQ b ofs -> P b ofs \/ Q b ofs),
      Mem.unchanged_on PQ m m'.
Proof. intros.
  split; intros.
    destruct (HPQ _ _ H).
      eapply HP; eassumption.
      eapply HQ; eassumption.
    destruct (HPQ _ _ H).
      eapply HP; eassumption.
      eapply HQ; eassumption.
Qed.

Lemma RGTgt_multicoreNOEFFECTS: forall mu m2 m2' (WD: SM_wd mu)
            (TgtHyp1: Mem.unchanged_on (fun b2 ofs => extBlocksTgt mu b2 = true /\
                                           ~ exists b1 d, foreign_of mu b1=Some (b2,d)) m2 m2')
            m1 m1' 
            (TgtHyp2: forall b ofs, Mem.unchanged_on (fun b' ofs' => b'=b /\ ofs'=ofs) m1 m1' ->
                      forall b2 d, foreign_of mu b = Some(b2,d) -> 
                           Mem.unchanged_on (fun b' ofs' => b'=b2 /\ ofs'=ofs+d) m2 m2')
            nu (WDnu: SM_wd nu)
           (FWD1: mem_forward m1 m1')
           (X1: forall b, locBlocksTgt nu b = true ->
                        DomTgt mu b = true /\ locBlocksTgt mu b = false)
           (X2: forall b1 b2 d, foreign_of mu b1 = Some(b2, d) -> 
                              locBlocksSrc nu b1 || locBlocksTgt nu b2 = true ->
                              pub_of nu b1 = Some(b2,d))
            (Unch1: Mem.unchanged_on (fun b ofs => locBlocksSrc nu b = true /\ 
                                           pubBlocksSrc nu b = false) m1 m1')
           (DECIDABILITYAXIOM: forall b2 (E: extBlocksTgt mu b2 = true),
                (exists b1 d, foreign_of mu b1 = Some(b2,d)) \/
                (~ exists b1 d, foreign_of mu b1=Some (b2,d))),
            Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'.
Proof. intros. 
split; intros b2; intros.
(*permissions*)
  destruct H.
  destruct (X1 _ H); clear X1.
  assert (extBlocksTgt mu b2 = true).
    unfold DomTgt in H2. rewrite H3 in H2; simpl in H2. assumption.
  destruct (DECIDABILITYAXIOM _ H4); clear DECIDABILITYAXIOM.
    destruct H5 as [b1 [dd FRGN]].
    specialize (X2 _ _ _ FRGN). rewrite H in X2.
    assert (local_of nu b1 = Some(b2,dd)). apply pub_in_local. apply X2; intuition. 
    eapply TgtHyp2; clear TgtHyp2; try eassumption.
    Focus 2. split. trivial. instantiate (1:=ofs-dd). omega.
    destruct (H1 _ _ H5); clear H1.
      eapply Fwd_unch; assumption.      
    eapply mem_unchanged_on_sub; try eassumption.
      intros. destruct H1; subst. split; trivial.
      eapply (local_DomRng _ WDnu _ _ _ H5).
  eapply TgtHyp1. split; trivial. assumption.
(*Values - same proof*)
  destruct H.
  destruct (X1 _ H); clear X1.
  assert (extBlocksTgt mu b2 = true).
    unfold DomTgt in H2. rewrite H3 in H2; simpl in H2. assumption.
  destruct (DECIDABILITYAXIOM _ H4); clear DECIDABILITYAXIOM.
    destruct H5 as [b1 [dd FRGN]].
    specialize (X2 _ _ _ FRGN). rewrite H in X2.
    assert (local_of nu b1 = Some(b2,dd)). apply pub_in_local. apply X2; intuition. 
    eapply TgtHyp2; clear TgtHyp2; try eassumption.
    Focus 2. split. trivial. instantiate (1:=ofs-dd). omega.
    destruct (H1 _ _ H5); clear H1.
      eapply Fwd_unch; assumption.      
    eapply mem_unchanged_on_sub; try eassumption.
      intros. destruct H1; subst. split; trivial.
      eapply (local_DomRng _ WDnu _ _ _ H5).
  eapply TgtHyp1. split; trivial. assumption.
Qed.