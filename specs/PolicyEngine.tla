---- MODULE PolicyEngine ----
(*******************************************
 * IAM-Like Policy Evaluation Engine       *
 * Verifies: deny-overrides-allow,         *
 * determinism, default-deny, monotonicity *
 *******************************************)

EXTENDS Naturals, FiniteSets

(***************************
 * FIXED PARAMETERS        *
 ***************************)

CONSTANTS
    Actions,          \* Set of all possible actions
    ResourceARNs,     \* Set of all possible resource ARNs
    MaxPolicies       \* Upper bound on number of policies

(***************************
 * TYPE DEFINITIONS        *
 ***************************)

EFFECTS == {"Allow", "Deny"}

\* Policy record:
\*   [effect |-> "Allow" | "Deny",
\*    actions |-> subset of Actions,
\*    resources |-> subset of ResourceARNs]
\*
\* A policy with actions = Actions means "all actions" (s3:star)
\* A policy with resources = ResourceARNs means "all resources" (star)

(* A policy matches an (action, resource) pair iff
   the action is in the policy's actions set AND
   the resource is in the policy's resources set *)
Matches(policy, action, resource) ==
    /\ action \in policy.actions
    /\ resource \in policy.resources

(***************************
 * THE EVALUATE FUNCTION   *
 ***************************)

(* Algorithm per design doc section 4.2:
   1. If any Deny matches → False
   2. Else if any Allow matches → True
   3. Else → False (default deny) *)
Evaluate(policies, action, resource) ==
    LET
        matchingDeny == { p \in policies : p.effect = "Deny" /\ Matches(p, action, resource) }
        matchingAllow == { p \in policies : p.effect = "Allow" /\ Matches(p, action, resource) }
    IN
        IF matchingDeny /= {} THEN FALSE
        ELSE IF matchingAllow /= {} THEN TRUE
        ELSE FALSE

(***************************
 * STATE SPACE             *
 ***************************)

VARIABLE policies

AllPolicyRecords ==
    [effect : EFFECTS, actions : SUBSET Actions, resources : SUBSET ResourceARNs]

TypeOK ==
    /\ policies \subseteq AllPolicyRecords
    /\ Cardinality(policies) <= MaxPolicies

(***************************
 * INIT & NEXT             *
 ***************************)

Init ==
    /\ policies = {}

AddPolicy ==
    /\ Cardinality(policies) < MaxPolicies
    /\ \E p \in AllPolicyRecords:
        /\ p \notin policies
        /\ policies' = policies \cup {p}

RemovePolicy ==
    /\ policies /= {}
    /\ \E p \in policies:
        policies' = policies \ {p}

Next ==
    \/ AddPolicy
    \/ RemovePolicy

Spec == Init /\ [][Next]_policies

(***************************
 * INVARIANTS              *
 ***************************)

(* INVARIANT 1: Deny overrides Allow.
   If any Deny policy matches the (action, resource) pair,
   evaluation MUST return False. *)
DenyOverrides ==
    \A action \in Actions, resource \in ResourceARNs:
        (\E p \in policies: p.effect = "Deny" /\ Matches(p, action, resource))
        => ~Evaluate(policies, action, resource)

(* INVARIANT 2: Default deny.
   An empty policy set denies everything. *)
DefaultDeny ==
    \A action \in Actions, resource \in ResourceARNs:
        ~Evaluate({}, action, resource)

(* INVARIANT 3: Determinism.
   Evaluate always returns a boolean. *)
Determinism ==
    \A action \in Actions, resource \in ResourceARNs:
        Evaluate(policies, action, resource) \in {TRUE, FALSE}

(* INVARIANT 4: Monotonicity under Allow additions.
   Adding an Allow policy never turns a previously-allowed
   request into denied. *)
Monotonicity ==
    \A newPolicy \in AllPolicyRecords:
        \A action \in Actions, resource \in ResourceARNs:
            (Evaluate(policies, action, resource)
             /\ newPolicy.effect = "Allow")
            => Evaluate(policies \cup {newPolicy}, action, resource)

(* INVARIANT 5: Removing an Allow policy never grants new access.
   Only removing a Deny can turn a denied request into an allowed one. *)
RemovalSafety ==
    \A removed \in policies:
        \A action \in Actions, resource \in ResourceARNs:
            (removed.effect = "Allow"
             /\ Evaluate(policies \ {removed}, action, resource))
            => Evaluate(policies, action, resource)

(* INVARIANT 6: If all policies are Allow, then access is granted
   iff at least one policy matches. *)
AllowOnlyNeverDeny ==
    (\A p \in policies: p.effect = "Allow")
    => (\A action \in Actions, resource \in ResourceARNs:
           Evaluate(policies, action, resource)
           <=> \E p \in policies: Matches(p, action, resource))

====================================================================================
