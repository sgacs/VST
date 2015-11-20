(** Heavily annotated for a tutorial introduction.
 ** See the Makefile for how to strip the annotations
 **)

(** First, import the entire Floyd proof automation system, which 
 ** includes the VeriC program logic and the MSL theory of separation logic
 **)
Require Import floyd.proofauto.

(** Import the theory of list segments.  This is not, strictly speaking,
 ** part of the Floyd system.  In principle, any user of Floyd can build
 ** theories of new data structures (list segments, trees, doubly linked
 ** lists, trees with cross edges, etc.).  We emphasize this by putting
 ** list_dt in the progs directory.   "dt" stands for "dependent types",
 ** as the theory uses Coq's dependent types to handle user-defined
 ** record fields.
 **)
Require Import progs.list_dt. Import LsegSpecial.

(** Import the [reverse.v] file, which is produced by CompCert's clightgen
 ** from reverse.c 
 **)
Require Import progs.reverse.
Definition CompSpecs' : compspecs.
Proof. make_compspecs1 prog. Defined.
Instance CompSpecs : compspecs.
Proof. make_compspecs2 CompSpecs'. Defined.

Local Open Scope logic.
(** Open the notation scope containing  !! * && operators of separation logic *)


(** The reverse.c program uses the linked list structure [struct list].
 ** This satisfies the linked-list pattern, in that it has one self-reference
 ** field (in this case, called [tail]) and arbitrary other fields.  The [Instance]
 ** explains (and proves) how [struct list] satisfies the [listspec] pattern.
 **)
Instance LS: listspec _list _tail.
Proof. eapply mk_listspec; reflexivity. Defined.

(**  An auxiliary definition useful in the specification of [sumlist] *)
Definition sum_int := fold_right Int.add Int.zero.

(** Specification of the [sumlist] function from reverse.c.  All the functions
 ** defined in the file, AND extern functions imported by the .c file,
 ** must be declared in this way.
 **)

Definition t_struct_list := Tstruct _list noattr.

Definition sumlist_spec :=
 DECLARE _sumlist
  WITH sh : share, contents : list int, p: val
  PRE [ _p OF (tptr (t_struct_list))] 
     PROP(readable_share sh) LOCAL (temp _p p)
     SEP (lseg LS sh (map Vint contents) p nullval)
  POST [ tint ]  
     PROP() LOCAL(temp ret_temp (Vint (sum_int contents)))
     SEP (lseg LS sh (map Vint contents) p nullval).

Definition reverse_spec :=
 DECLARE _reverse
  WITH sh : share, contents : list val, p: val
  PRE  [ _p OF (tptr t_struct_list) ]
     PROP (writable_share sh)
     LOCAL (temp _p p)
     SEP (lseg LS sh contents p nullval)
  POST [ (tptr t_struct_list) ]
    EX p:val,
     PROP () LOCAL (temp ret_temp p) 
     SEP (lseg LS sh (rev contents) p nullval).

Definition main_spec :=
 DECLARE _main
  WITH u : unit
  PRE  [] main_pre prog u
  POST [ tint ] main_post prog u.

(** Declare the types of all the global variables.  [Vprog] must list
 ** the globals in the same order as in reverse.c file (and as in reverse.v).
 **)
Definition Vprog : varspecs := 
          (_three, Tarray t_struct_list 3 noattr)::nil.

(** Declare all the functions, in exactly the same order as they
 ** appear in reverse.c (and in reverse.v).
 **)
Definition Gprog : funspecs := 
    sumlist_spec :: reverse_spec :: main_spec::nil.

(** Two little equations about the list_cell predicate *)
Lemma list_cell_eq': forall sh i p ,
   list_cell LS sh (Vint i) p * field_at_ sh list_struct (DOT _tail) p = 
   field_at sh t_struct_list (DOT _head) (Vint i) p * field_at_ sh list_struct (DOT _tail) p.
Proof.
  intros.
  rewrite list_cell_link_join_nospacer by reflexivity.
  unfold data_at. unfold list_data, add_link_back, fold_reptype.
  rewrite !eq_rect_r_eq. rewrite <- eq_rect_eq. unfold list_rect; simpl.
  rewrite !eq_rect_r_eq. 
  unfold_field_at 1%nat. auto.
Qed.

Lemma memory_block_resolve:
  forall A B C D sh n p,
   sepalg.nonidentity sh ->
   (A * (C && memory_block sh n p)) && (B * (D && memory_block sh n p)) |--
   (A && B) * (C && D && memory_block sh n p).
Admitted.  (* should work since memory_block is a precise predicate *)

Lemma field_at_resolve1:
  forall A B sh t gfs v p,
   sepalg.nonidentity sh ->
   (A * field_at_ sh t gfs p) && (B * field_at sh t gfs v p) |--
   (A && B) * field_at sh t gfs v p.
Proof.
intros.
apply derives_trans with
 ((A * (TT && field_at_ sh t gfs p)) && (B * (field_at sh t gfs v p && field_at_ sh t gfs p))).
apply andp_right. rewrite TT_andp.
  apply andp_left1. auto.
  apply andp_left2. apply sepcon_derives; auto. apply andp_right; cancel.
  rewrite field_at__memory_block. 
  eapply derives_trans; [apply memory_block_resolve; auto | ].
  rewrite TT_andp. apply sepcon_derives; auto. apply andp_left1; auto.
Qed.  

Lemma list_cell_eq'': forall sh i p q ,
   sepalg.nonidentity sh ->
   list_cell LS sh (Vint i) p * field_at sh list_struct (DOT _tail) q p = 
   field_at sh t_struct_list (DOT _head) (Vint i) p * field_at sh list_struct (DOT _tail) q p.
Proof.
  intros.
  apply pred_ext.
  rewrite <- (andp_dup (field_at sh list_struct (DOT _tail) q p)) at 1.
  eapply derives_trans; [apply distrib_sepcon_andp | ].
  eapply derives_trans; [apply andp_derives; [ | apply derives_refl ] |].
  apply sepcon_derives; [apply derives_refl | ].
  apply field_at_field_at_.
  rewrite list_cell_eq'.
  eapply derives_trans; [apply field_at_resolve1; auto | ].
  apply sepcon_derives; auto. apply andp_left1; auto.
  rewrite <- (andp_dup (field_at sh list_struct (DOT _tail) q p)) at 1.
  eapply derives_trans; [apply distrib_sepcon_andp | ].
  eapply derives_trans; [apply andp_derives; [ | apply derives_refl ] |].
  apply sepcon_derives; [apply derives_refl | ].
  apply field_at_field_at_.
  rewrite <- list_cell_eq'.
  eapply derives_trans; [apply field_at_resolve1; auto | ].
  apply sepcon_derives; auto. apply andp_left1; auto.
Qed.

(** Here's a loop invariant for use in the body_sumlist proof *)
Definition sumlist_Inv (sh: share) (contents: list int) (p: val) : environ->mpred :=
          (EX cts1: list int, EX cts2: list int, EX t: val, 
            PROP (contents = cts1++cts2) 
            LOCAL (temp _t t; temp _s (Vint (sum_int cts1)))
            SEP ( lseg LS sh (map Vint cts1) p t ; lseg LS sh (map Vint cts2) t nullval)).

Lemma sum_int_app:
  forall a b, sum_int (a++b) = Int.add (sum_int a) (sum_int b).
Proof.
intros.
induction a; simpl. rewrite Int.add_zero_l; auto.
rewrite IHa. rewrite Int.add_assoc. auto.
Qed.

(** For every function definition in the C program, prove that the
 ** function-body (in this case, f_sumlist) satisfies its specification
 ** (in this case, sumlist_spec).  
 **)
Lemma body_sumlist: semax_body Vprog Gprog f_sumlist sumlist_spec.
Proof.
(** Here is the standard way to start a function-body proof:  First,
 ** start-function; then forward.
 **)
start_function.
forward.  (* s = 0; *) 
forward.  (* t = p; *)
forward_while (sumlist_Inv sh contents p).
* (* Prove that current precondition implies loop invariant *)
Exists (@nil int) contents p.
entailer!. cancel.
* (* Prove that loop invariant implies typechecking condition *)
entailer!.
* (* Prove that loop body preserves invariant *)
focus_SEP 1; apply semax_lseg_nonnull; [ | intros h' r y ? ?].
entailer!.
destruct cts2; inversion H0; clear H0; subst_any.
gather_SEP 0 1. 
rewrite list_cell_eq'' by auto.
Intros.  (* flatten the SEP *)
forward.  (* h = t->head; *)
forward.  (*  t = t->tail; *)
forward.  (* s = s + h; *)
Exists (cts1++[i],cts2,y).
name h _h.
entailer. 
apply andp_right.
apply prop_right.
split.
rewrite app_ass; reflexivity.
 f_equal. rewrite sum_int_app. f_equal. simpl. apply Int.add_zero.
rewrite map_app. simpl map.
eapply derives_trans; [ | apply (lseg_cons_right_list LS) with (y:=t); auto].
rewrite list_cell_eq'' by auto.
cancel.
* (* After the loop *)
forward.  (* return s; *)
destruct cts2; [| inversion H]. rewrite <- app_nil_end.
entailer!.
Qed.

Definition reverse_Inv (sh: share) (contents: list val) : environ->mpred :=
          (EX cts1: list val, EX cts2 : list val, EX w: val, EX v: val,
            PROP (contents = rev cts1 ++ cts2) 
            LOCAL (temp _w w; temp _v v)
            SEP (lseg LS sh cts1 w nullval;
                   lseg LS sh cts2 v nullval)).

Lemma body_reverse: semax_body Vprog Gprog f_reverse reverse_spec.
Proof.
start_function.
name w_ _w.
forward.  (* w = NULL; *)
forward.  (* v = p; *)
forward_while (reverse_Inv sh contents).
* (* precondition implies loop invariant *)
Exists (@nil val) contents (Vint (Int.repr 0)) p.
rewrite lseg_eq by (simpl; auto).
entailer!.
* (* loop invariant implies typechecking of loop condition *)
entailer!.
* (* loop body preserves invariant *)
focus_SEP 1; apply semax_lseg_nonnull;
        [entailer | intros h r y ? ?; simpl].
subst cts2.
forward. (* t = v->tail; *)
forward. (* v->tail = w; *)
replace_SEP 1 (field_at sh t_struct_list (DOT _tail) w v) by entailer!.
forward.  (*  w = v; *)
forward.  (* v = t; *)
(* at end of loop body, re-establish invariant *)
Exists (h::cts1,r,v,y).
entailer!.  (* smt_test verif_reverse_example2 *)
 - rewrite app_ass. auto.
 - rewrite (lseg_unroll _ sh (h::cts1)).
   apply orp_right2.
   unfold lseg_cons.
   apply andp_right.
   + apply prop_right.
      destruct w_; try contradiction; intro Hx; inv Hx.
   + Exists h cts1 w.
      entailer!.
* (* after the loop *)
forward.  (* return w; *)
Exists w_; entailer!.
rewrite <- app_nil_end, rev_involutive.
auto.
Qed.

(** The next two lemmas concern the extern global initializer, 
 ** struct list three[] = {{1, three+1}, {2, three+2}, {3, NULL}};
 ** This is equivalent to a linked list of three elements [1,2,3].
 ** Here is how we prove that.
 **)

(** First, "list_init_rep three 0 [1,2,3]" is computes to the initializer sequence,
**      {1, three+1, 2, three+2, 3, NULL}
**) 
Fixpoint list_init_rep (i: ident) (ofs: Z) (l: list int) :=
 match l with 
 | nil => nil
 | j::nil => Init_int32 j :: Init_int32 Int.zero :: nil
 | j::jl => Init_int32 j :: Init_addrof i (Int.repr (ofs+8)) :: list_init_rep i (ofs+8) jl
 end.

Lemma gvar_uniq:
  forall i v v' rho, gvar i v rho -> gvar i v' rho -> v=v'.
Proof.
intros.
hnf in H,H0.
destruct (Map.get (ve_of rho) i) as [[? ?]|]; try contradiction.
destruct (ge_of rho i); try contradiction.
subst; auto.
Qed.

Lemma gvar_size_compatible:
  forall i s rho t, 
    gvar i s rho -> 
    sizeof cenv_cs t <= Int.modulus ->
    size_compatible t s.
Proof.
intros.
hnf in H. destruct (Map.get (ve_of rho) i) as [[? ? ] | ]; try contradiction.
destruct (ge_of rho i); try contradiction.
subst s.
simpl; auto.
Qed.

Lemma gvar_align_compatible:
  forall i s rho t, 
    gvar i s rho -> 
    align_compatible t s.
Proof.
intros.
hnf in H. destruct (Map.get (ve_of rho) i) as [[? ? ] | ]; try contradiction.
destruct (ge_of rho i); try contradiction.
subst s.
simpl; auto.
exists 0. reflexivity.
Qed.

Lemma mapsto_pointer_type:
  forall sh t1 t2 a,
    mapsto sh (Tpointer t1 a) = mapsto sh (Tpointer t2 a).
Proof.
intros.
extensionality v1 v2.
unfold mapsto.
simpl.
unfold type_is_volatile; simpl.
destruct (attr_volatile a); auto.
Qed.

Lemma gvar_offset: forall i v rho,
  gvar i v rho -> exists b, v = Vptr b Int.zero.
Proof.
intros.
hnf in H. destruct (Map.get (ve_of rho) i) as [[? ? ] | ]; try contradiction.
destruct (ge_of rho i); try contradiction.
eauto.
Qed.

Lemma setup_globals:
 forall x,
  (PROP  ()
   LOCAL  (gvar _three x)
   SEP 
   (mapsto Ews tuint (offset_val (Int.repr 0) x) (Vint (Int.repr 1));
    mapsto Ews (tptr t_struct_list) (offset_val (Int.repr 4) x)
        (offset_val (Int.repr 8) x);
   mapsto Ews tuint (offset_val (Int.repr 8) x) (Vint (Int.repr 2));
   mapsto Ews (tptr t_struct_list) (offset_val (Int.repr 12) x)
       (offset_val (Int.repr 16) x);
   mapsto Ews tuint (offset_val (Int.repr 16) x) (Vint (Int.repr 3));
   mapsto Ews tuint (offset_val (Int.repr 20) x) (Vint (Int.repr 0))))
  |-- PROP() LOCAL(gvar _three x) 
        SEP (lseg LS Ews (map Vint (Int.repr 1 :: Int.repr 2 :: Int.repr 3 :: nil))
                  x nullval).
Proof.
  intros.
  entailer.
 rewrite !sepcon_assoc.
  apply gvar_offset in H. destruct H as [b ?]. subst x. simpl.
  repeat rewrite Int.add_zero_l.
  apply @lseg_unroll_nonempty1 with (Vptr b (Int.repr 8));
   [intro Hx; inv Hx | apply I | simpl ].
  rewrite <- (sepcon_assoc (list_cell LS _ _ _)).
  rewrite list_cell_eq'' by auto.
  repeat rewrite field_at_data_at. unfold data_at, field_at.
  unfold field_address.
  repeat ((rewrite if_true || rewrite prop_true_andp);
    [ | repeat split; 
         try solve [red; normalize; compute; congruence];
         try solve [exists 0; rewrite Z.mul_0_l; reflexivity];
         try solve [exists 1; reflexivity];
         try solve [left; reflexivity];
         try solve [right; left; reflexivity]
    ]).
 simpl.
 unfold data_at', at_offset; simpl.
 unfold mapsto. simpl. rewrite !if_true by auto.
 rewrite sepcon_assoc.
 apply sepcon_derives; [ apply derives_refl | ].  
 apply sepcon_derives; [ apply derives_refl | ].
Admitted.
(*
  simpl_data_at; repeat rewrite   Int.add_zero_l.
  repeat (rewrite prop_true_andp; [ | repeat split; try computable; try reflexivity]).
  unfold nested_field_offset2; simpl.
  apply sepcon_derives; auto.
  apply sepcon_derives; auto.
  apply @lseg_unroll_nonempty1 with (Vptr b (Int.repr 16));
   [intro Hx; inv Hx | apply I | simpl ].
  rewrite list_cell_eq; repeat rewrite field_at_data_at;
     unfold field_address; 
     repeat (rewrite if_true; [ | repeat split; try computable]).
  simpl_data_at; repeat rewrite   Int.add_zero_l.
  repeat (rewrite prop_true_andp; [ | repeat split; try computable; try reflexivity]).
  unfold nested_field_offset2; simpl.
  apply sepcon_derives; auto.
  apply sepcon_derives; auto.
  apply @lseg_unroll_nonempty1 with nullval;
   [intro Hx; inv Hx | reflexivity | simpl].
  rewrite list_cell_eq; repeat rewrite field_at_data_at;
     unfold field_address; 
     repeat (rewrite if_true; [ | repeat split; try computable]).
    simpl_data_at; repeat rewrite   Int.add_zero_l.
  repeat (rewrite prop_true_andp; [ | repeat split; try computable; try reflexivity]).
  normalize.
  apply sepcon_derives; auto.
{
  apply derives_refl'.
  unfold mapsto. simpl. f_equal. f_equal. f_equal.
  apply prop_ext; intuition congruence.
}
  unfold nested_field_offset2; simpl.   exists 5; computable.
  unfold nested_field_offset2; simpl.   exists 4; computable.
  compute; congruence.
  simpl; exists 4; compute; congruence.
  compute; congruence.
  simpl; exists 4; compute; congruence.
  unfold nested_field_offset2; simpl.  exists 3; computable.
  unfold nested_field_offset2; simpl.  exists 2; computable.
  compute; congruence.
  simpl; exists 2; compute; congruence.
  compute; congruence.
  simpl; exists 2; compute; congruence.
  unfold nested_field_offset2; simpl.  exists 0; computable.
  compute; congruence.
  simpl; exists 0; compute; congruence.
  compute; congruence.
  simpl; exists 0; compute; congruence.
Qed.
*)
Lemma body_main:  semax_body Vprog Gprog f_main main_spec.
Proof.
name r _r.
name s _s.
name three _three.
start_function.
 change (Tpointer
     (Tstruct 8%positive {| attr_volatile := false; attr_alignas := None |})
     noattr) with (tptr t_struct_list).
eapply semax_pre; [
  eapply derives_trans; [ | apply (setup_globals three) ] | ].
 entailer!.
forward_call (*  r = reverse(three); *)
  (Ews, map Vint [Int.repr 1; Int.repr 2; Int.repr 3], three) r'.
rewrite <- map_rev. simpl rev.
forward_call  (* s = sumlist(r); *)
   (Ews, Int.repr 3 :: Int.repr 2 :: Int.repr 1 :: nil, r') s'.
forward.  (* return s; *)
Qed.

Existing Instance NullExtension.Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct; simpl.
semax_func_skipn.
semax_func_cons body_sumlist.
semax_func_cons body_reverse.
semax_func_cons body_main.
apply semax_func_nil.
Qed.

