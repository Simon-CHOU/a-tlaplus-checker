---- MODULE MultipartUpload ----
(*******************************************
 * Multipart Upload State Machine          *
 * Verifies: no state conflicts, parts     *
 * cleanup on abort, GC correctness,       *
 * upload ID uniqueness                    *
 *                                         *
 * Implementation contract (Store.hs):     *
 * - uploads persist in 'initiated' or     *
 *   'completed' state only               *
 * - abortMultipartUpload DELETES the      *
 *   upload entirely (both parts + record) *
 * - getMultipartUpload returns only       *
 *   'initiated' uploads                  *
 * - cleanupExpiredUploads deletes expired *
 *   'initiated' uploads (7-day expiry)   *
 * - UploadInProgress exists in Types.hs   *
 *   as a 4th constructor but is not      *
 *   currently used as a separate DB state *
 *******************************************)

EXTENDS Naturals, FiniteSets

(***************************
 * FIXED PARAMETERS        *
 ***************************)

CONSTANTS
    UploadIds,       \* Set of possible upload IDs
    PartNums,        \* Set of possible part numbers (1..N)
    MaxUploads       \* Bounded model: max concurrent uploads

(***************************
 * TYPE DEFINITIONS        *
 ***************************)

\* Implementation uses 4-state type (UploadInitiated, UploadInProgress,
\* UploadCompleted, UploadAborted) but the DB only persists 'initiated'
\* and 'completed' — abort deletes the record entirely.
STATES == {"initiated", "completed"}

(*
   Each upload is a record:
   [id |-> uploadId,
    state |-> "initiated" | "completed",
    parts |-> subset of PartNums,
    expired |-> TRUE/FALSE (whether past 7-day expiry window)]
*)

(***************************
 * STATE SPACE             *
 ***************************)

VARIABLE uploads    \* Set of upload records

AllUploadRecords ==
    [id : UploadIds, state : STATES, parts : SUBSET PartNums, expired : {TRUE, FALSE}]

TypeOK ==
    /\ uploads \subseteq AllUploadRecords
    /\ Cardinality(uploads) <= MaxUploads
    \* No duplicate IDs (matches UNIQUE(upload_id) in SQLite)
    /\ \A u1, u2 \in uploads: u1.id = u2.id => u1 = u2

(***************************
 * INIT & NEXT             *
 ***************************)

Init ==
    /\ uploads = {}

(***************************
 * OPERATIONS              *
 ***************************)

(* CreateMultipartUpload: INSERT with state='initiated', expires_at = now + 7d *)
CreateMultipartUpload ==
    /\ Cardinality(uploads) < MaxUploads
    /\ \E id \in UploadIds:
        /\ \A u \in uploads: u.id /= id   \* ID not already in use
        /\ \E expired \in {TRUE, FALSE}:
            /\ uploads' = uploads \cup {[id |-> id, state |-> "initiated",
                                         parts |-> {}, expired |-> expired]}

(* UploadPart: add a part to an 'initiated' upload
   Matches addPart: INSERT OR REPLACE into multipart_parts *)
UploadPart ==
    /\ \E u \in uploads:
        /\ u.state = "initiated"
        /\ \E partNum \in PartNums:
            /\ partNum \notin u.parts
            /\ uploads' = (uploads \ {u})
                          \cup {[u EXCEPT !.parts = u.parts \cup {partNum}]}

(* CompleteMultipartUpload: transition 'initiated' -> 'completed', clear parts
   Matches completeMultipartUpload: UPDATE state='completed' *)
CompleteMultipartUpload ==
    /\ \E u \in uploads:
        /\ u.state = "initiated"
        /\ u.parts /= {}  \* Must have at least one part
        /\ uploads' = (uploads \ {u})
                      \cup {[u EXCEPT !.state = "completed", !.parts = {}]}

(* AbortUpload: DELETE the upload entirely.
   Matches abortMultipartUpload in Store.hs:
   DELETE FROM multipart_parts WHERE upload_id = ?
   DELETE FROM multipart_uploads WHERE upload_id = ?
   The upload record is removed — no "aborted" state is persisted. *)
AbortUpload ==
    /\ \E u \in uploads:
        /\ u.state = "initiated"
        /\ uploads' = uploads \ {u}

(* ExpireUpload: time passes, upload becomes eligible for GC.
   Matches expires_at < now check in cleanupExpiredUploads. *)
ExpireUpload ==
    /\ \E u \in uploads:
        /\ u.expired = FALSE
        /\ uploads' = (uploads \ {u})
                      \cup {[u EXCEPT !.expired = TRUE]}

(* GarbageCollect: delete expired 'initiated' uploads.
   Matches cleanupExpiredUploads which calls abortMultipartUpload
   on each expired upload — same as AbortUpload but gated on expired flag. *)
GarbageCollect ==
    /\ \E u \in uploads:
        /\ u.state = "initiated"
        /\ u.expired = TRUE
        /\ uploads' = uploads \ {u}

(* Note: There is no CleanupTerminal action in the implementation.
   Completed upload records persist indefinitely in the database;
   there is no background job that removes them. *)

Next ==
    \/ CreateMultipartUpload
    \/ UploadPart
    \/ CompleteMultipartUpload
    \/ AbortUpload
    \/ GarbageCollect
    \/ ExpireUpload

Spec == Init /\ [][Next]_uploads

(***************************
 * INVARIANTS              *
 ***************************)

(* INVARIANT 1: No upload can be in an invalid state.
   Trivially true since state is a single value from STATES. *)
NoStateConflict ==
    \A u \in uploads: u.state \in STATES

(* INVARIANT 2: Completed uploads have no parts.
   (Aborted uploads are deleted, so they don't appear in uploads at all.) *)
CleanupOnTerminal ==
    \A u \in uploads:
        u.state = "completed" => u.parts = {}

(* INVARIANT 3: Only initiated uploads can have parts. *)
OnlyInitiatedHasParts ==
    \A u \in uploads:
        u.parts /= {} => u.state = "initiated"

(* INVARIANT 4: Upload IDs are unique within each upload record.
   Enforced structurally by the CreateMultipartUpload action checking
   that no existing upload has the same ID. *)

====================================================================================
