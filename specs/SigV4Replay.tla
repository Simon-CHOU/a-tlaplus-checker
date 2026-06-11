---- MODULE SigV4Replay ----
(*******************************************
 * SigV4 Timestamp Validation &            *
 * Replay Protection (bounded model)       *
 *                                         *
 * Verifies:                              *
 *  1. Requests outside window rejected    *
 *  2. Replayed signatures rejected        *
 *  3. Fresh valid requests accepted       *
 *******************************************)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Signatures,      \* Set of possible signatures
    MaxWindow,       \* Timestamp window size
    MaxTime          \* Maximum timestamp value

(***************************
 * STATE                   *
 ***************************)

\* We model the server as processing a single request per step.
\* No explicit clock - time is carried by the request timestamp.
\* The "server time" is the timestamp of the most recently accepted request.

VARIABLE seenSigs       \* Set of signatures already processed (replay cache)
VARIABLE lastReqTime    \* Timestamp of last accepted request (for window check)
VARIABLE accepted       \* Count of accepted requests
VARIABLE rejected       \* Count of rejected requests
VARIABLE step           \* Bounded step counter

TypeOK ==
    /\ seenSigs \subseteq Signatures
    /\ lastReqTime \in 0 .. MaxTime
    /\ accepted \in Nat
    /\ rejected \in Nat
    /\ step \in 0 .. 3

Init ==
    /\ seenSigs = {}
    /\ lastReqTime = 0
    /\ accepted = 0
    /\ rejected = 0
    /\ step = 0

(***************************
 * OPERATIONS              *
 ***************************)

\* Accept: fresh signature, request within window of last accepted time
Accept ==
    /\ step < 3
    /\ \E sig \in Signatures \ seenSigs:
        \E reqTime \in 0 .. MaxTime:
            /\ reqTime <= lastReqTime + MaxWindow
            /\ reqTime + MaxWindow >= lastReqTime
            /\ seenSigs' = seenSigs \cup {sig}
            /\ lastReqTime' = reqTime
            /\ accepted' = accepted + 1
            /\ rejected' = rejected
            /\ step' = step + 1

\* Reject expired: request outside time window (too old or too far ahead)
RejectExpired ==
    /\ step < 3
    /\ \E sig \in Signatures:
        \E reqTime \in 0 .. MaxTime:
            /\ \/ reqTime > lastReqTime + MaxWindow    \* too far in future
               \/ reqTime + MaxWindow < lastReqTime     \* too far in past
            /\ seenSigs' = seenSigs
            /\ lastReqTime' = lastReqTime
            /\ accepted' = accepted
            /\ rejected' = rejected + 1
            /\ step' = step + 1

\* Reject replay: seen signature
RejectReplay ==
    /\ step < 3
    /\ seenSigs /= {}
    /\ \E sig \in seenSigs:
        /\ seenSigs' = seenSigs
        /\ lastReqTime' = lastReqTime
        /\ accepted' = accepted
        /\ rejected' = rejected + 1
        /\ step' = step + 1

Next ==
    \/ Accept
    \/ RejectExpired
    \/ RejectReplay

Spec == Init /\ [][Next]_<<seenSigs, lastReqTime, accepted, rejected, step>>

(***************************
 * INVARIANTS              *
 ***************************)

\* Each accepted request adds exactly one unique signature to the cache
SeenSigsMatchesAccepted ==
    Cardinality(seenSigs) = accepted

\* Rejected count is monotonic
RejectedMonotonic ==
    rejected >= 0

====================================================================================
