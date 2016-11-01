Require Import progs.conclib.
Require Import progs.incr.

Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Definition acquire_spec := DECLARE _acquire acquire_spec.
Definition release_spec := DECLARE _release release_spec.
Definition makelock_spec := DECLARE _makelock (makelock_spec _).
Definition freelock_spec := DECLARE _freelock (freelock_spec _).
Definition spawn_spec := DECLARE _spawn spawn_spec.
Definition freelock2_spec := DECLARE _freelock2 (freelock2_spec _).
Definition release2_spec := DECLARE _release2 release2_spec.

Definition cptr_lock_inv ctr := EX z : Z, data_at Ews tint (Vint (Int.repr z)) ctr.

Definition incr_spec :=
 DECLARE _incr
  WITH ctr : val, sh : share, lock : val
  PRE [ ]
         PROP  (readable_share sh)
         LOCAL (gvar _ctr ctr; gvar _ctr_lock lock)
         SEP   (lock_inv sh lock (cptr_lock_inv ctr))
  POST [ tvoid ]
         PROP ()
         LOCAL ()
         SEP (lock_inv sh lock (cptr_lock_inv ctr)).

Definition read_spec :=
 DECLARE _read
  WITH ctr : val, sh : share, lock : val
  PRE [ ]
         PROP  (readable_share sh)
         LOCAL (gvar _ctr ctr; gvar _ctr_lock lock)
         SEP   (lock_inv sh lock (cptr_lock_inv ctr))
  POST [ tint ] EX z : Z,
         PROP ()
         LOCAL (temp ret_temp (Vint (Int.repr z)))
         SEP (lock_inv sh lock (cptr_lock_inv ctr)).

Definition thread_lock_inv sh ctr lockc lockt := selflock (lock_inv sh lockc (cptr_lock_inv ctr)) sh lockt.

Definition thread_func_spec :=
 DECLARE _thread_func
  WITH y : val, x : val * share * val * val
  PRE [ _args OF (tptr tvoid) ]
         let '(ctr, sh, lock, lockt) := x in
         PROP  ()
         LOCAL (temp _args y; gvar _ctr ctr; gvar _ctr_lock lock; gvar _thread_lock lockt)
         SEP   ((!!readable_share sh && emp); lock_inv sh lock (cptr_lock_inv ctr);
                lock_inv sh lockt (thread_lock_inv sh ctr lock lockt))
  POST [ tptr tvoid ]
         PROP ()
         LOCAL ()
         SEP (emp).

Definition main_spec :=
 DECLARE _main
  WITH u : unit
  PRE  [] main_pre prog nil u
  POST [ tint ] main_post prog nil u.

Definition Gprog : funspecs := augment_funspecs prog [acquire_spec; release_spec; release2_spec; makelock_spec;
  freelock_spec; freelock2_spec; spawn_spec; incr_spec; read_spec; thread_func_spec; main_spec].

Lemma ctr_inv_precise : forall p,
  precise (cptr_lock_inv p).
Proof.
  intro; eapply derives_precise, data_at__precise with (sh := Ews)(t := tint); auto.
  intros ? (? & H); apply data_at_data_at_ in H; eauto.
Qed.

Lemma ctr_inv_positive : forall ctr,
  positive_mpred (cptr_lock_inv ctr).
Proof.
  intro; apply ex_positive; auto.
Qed.

Lemma body_incr: semax_body Vprog Gprog f_incr incr_spec.
Proof.
  start_function.
  forward.
  forward_call (lock, sh, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  unfold cptr_lock_inv at 2; simpl.
  Intro z.
  forward.
  forward.
  rewrite field_at_isptr; normalize.
  forward_call (lock, sh, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { unfold cptr_lock_inv.
    subst Frame; instantiate (1 := []); Exists (z + 1); entailer!.
    lock_props; [apply ctr_inv_precise | apply ctr_inv_positive]. }
  forward.
Qed.

Lemma body_read : semax_body Vprog Gprog f_read read_spec.
Proof.
  start_function.
  forward_call (lock, sh, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  unfold cptr_lock_inv at 2; simpl.
  Intro z.
  forward.
  rewrite data_at_isptr; Intros.
  forward_call (lock, sh, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { unfold cptr_lock_inv.
    subst Frame; instantiate (1 := []); Exists z; entailer!.
    lock_props; [apply ctr_inv_precise | apply ctr_inv_positive]. }
  forward.
  Exists z; entailer!.
Qed.

Lemma body_thread_func : semax_body Vprog Gprog f_thread_func thread_func_spec.
Proof.
  start_function.
  Intros.
  forward.
  forward_call (ctr, sh, lock).
  forward_call (lockt, sh, lock_inv sh lock (cptr_lock_inv ctr), thread_lock_inv sh ctr lock lockt).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { subst Frame; instantiate (1 := []).
    unfold thread_lock_inv; simpl.
    rewrite selflock_eq at 5; cancel.
    eapply derives_trans; [apply lock_inv_later | cancel].
    lock_props; apply selflock_rec. }
  forward.
Qed.

Lemma lock_struct : forall p, data_at_ Ews (Tstruct _lock_t noattr) p |-- data_at_ Ews tlock p.
Proof.
  intros.
  unfold data_at_, field_at_; unfold_field_at 1%nat.
  unfold field_at; simpl.
  rewrite field_compatible_cons; simpl; entailer.
  (* temporarily broken *)
Admitted.

Lemma body_main:  semax_body Vprog Gprog f_main main_spec.
Proof.
  name ctr _ctr; name lockt _thread_lock; name lock _ctr_lock.
  start_function.
  forward.
  forward.
  forward.
  forward_call (lock, Ews, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { rewrite (sepcon_comm _ (fold_right _ _ _)); apply sepcon_derives; [cancel | apply lock_struct]. }
  rewrite field_at_isptr; Intros.
  forward_call (lock, Ews, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { subst Frame; instantiate (1 := [data_at_ Ews (Tstruct 2%positive noattr) lockt]).
    unfold cptr_lock_inv; simpl.
    Exists 0; cancel.
    lock_props; [apply ctr_inv_precise | apply ctr_inv_positive]. }
  (* need to split off shares for the locks here *)
  destruct split_Ews as (sh1 & sh2 & ? & ? & Hsh).
  forward_call (lockt, Ews, thread_lock_inv sh1 ctr lock lockt).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { rewrite (sepcon_comm _ (fold_right _ _ _)); apply sepcon_derives; [cancel | apply lock_struct]. }
  get_global_function'' _thread_func.
  apply extract_exists_pre; intros f_.

  (* Spawn will be tricky. *)
(*  forward_call (f_, Vint (Int.repr 0), (ctr, sh1, lock, lockt),
    fun (x : (val * share * val * val)) (_ : val) => let '(ctr, sh, lock, tlock) := x in
     !!readable_share sh && emp * lock_inv sh lock (cptr_lock_inv ctr) *
     lock_inv sh lockt (thread_lock_inv sh ctr lock lockt)).*)
  evar (Frame : list mpred).
  rewrite <- seq_assoc; eapply semax_seq'.
  { eapply semax_pre, semax_call_id0 with
      (argsig := [(_f, tptr voidstar_funtype); (xsemax_conc._args, tptr tvoid)])(P := [])
      (Q := [gvar _thread_func f_; temp _lockt lockt; temp _lockc lock; gvar _ctr ctr; gvar _thread_lock lockt;
             gvar _ctr_lock lock])(R := Frame)(ts := [(val * share * val * val)%type])
      (A := rmaps.ProdType (rmaps.ProdType (rmaps.ConstType (val * val)) (rmaps.DependentType 0))
            (rmaps.ArrowType (rmaps.DependentType 0) (rmaps.ArrowType (rmaps.ConstType val) rmaps.Mpred)))
      (x := (f_, Vint (Int.repr 0), (ctr, sh1, lock, lockt),
             fun (x : (val * share * val * val)) (_ : val) => let '(ctr, sh, lock, lockt) := x in
               !!readable_share sh && emp * lock_inv sh lock (cptr_lock_inv ctr) *
               lock_inv sh lockt (thread_lock_inv sh ctr lock lockt))); try reflexivity.
    entailer!.
    Exists _args (fun x : val * share * val * val => let '(ctr, sh, lock, lockt) := x in
      [(_ctr, ctr); (_ctr_lock, lock); (_thread_lock, lockt)]); entailer.
    rewrite !sepcon_assoc; apply sepcon_derives.
    { apply derives_refl'; f_equal; f_equal.
      - extensionality.
        destruct x as (?, (((?, ?), ?), ?)); simpl.
        rewrite <- !sepcon_assoc; reflexivity.
      - extensionality.
        destruct x as (?, (((?, ?), ?), ?)); reflexivity. }
    erewrite <- lock_inv_share_join; try apply Hsh; auto.
    erewrite <- (lock_inv_share_join _ _ Ews); try apply Hsh; auto.
    entailer!. }
  after_forward_call.
  rewrite void_ret; subst Frame; normalize.
  forward_call (ctr, sh2, lock).
  forward_call (lockt, sh2, thread_lock_inv sh1 ctr lock lockt).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  forward_call (ctr, sh2, lock).
  Intro z.
  forward_call (lock, sh2, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  forward_call (lockt, Ews, sh1, |>lock_inv sh1 lock (cptr_lock_inv ctr), |>thread_lock_inv sh1 ctr lock lockt).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { subst Frame; instantiate (1 := [lock_inv Ews lock (cptr_lock_inv ctr); cptr_lock_inv ctr]); simpl; cancel.
    unfold thread_lock_inv.
    rewrite selflock_eq at 2.
    rewrite sepcon_assoc, <- (sepcon_assoc (lock_inv _ lockt _)), (sepcon_comm (lock_inv _ lockt _)).
    apply sepalg.join_comm in Hsh.
    repeat rewrite <- sepcon_assoc; erewrite lock_inv_share_join; eauto; cancel.
    eapply derives_trans.
    { apply sepcon_derives; [apply lock_inv_later | apply derives_refl]. }
    erewrite lock_inv_share_join; eauto; cancel.
    lock_props.
    - apply later_positive, selflock_positive, lock_inv_positive.
    - unfold rec_inv.
      rewrite selflock_eq at 1.
      rewrite later_sepcon; f_equal.
      apply lock_inv_later_eq. }
  forward_call (lock, Ews, cptr_lock_inv ctr).
  { apply prop_right; rewrite sem_cast_neutral_ptr; rewrite sem_cast_neutral_ptr; auto. }
  { subst Frame; instantiate (1 := [data_at_ Ews tlock lockt]); simpl; cancel; lock_props.
    apply ctr_inv_positive. }
  forward.
Qed.

Definition extlink := ext_link_prog prog.

Definition Espec := add_funspecs (Concurrent_Espec unit _ extlink) extlink Gprog.
Existing Instance Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct; simpl.
repeat (apply semax_func_cons_ext_vacuous; [reflexivity | reflexivity | ]).
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons_ext.
semax_func_cons body_incr.
semax_func_cons body_read.
semax_func_cons body_thread_func.
semax_func_cons body_main.
Qed.
