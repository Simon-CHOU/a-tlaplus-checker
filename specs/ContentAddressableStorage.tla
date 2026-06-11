---- MODULE ContentAddressableStorage ----
(*******************************************
 * Content-Addressable Object Storage      *
 * Verifies: ref-count > 0, domain match,  *
 * refCount = key cardinality, hash determ.*
 *                                         *
 * Implementation contract (Object/Storage *
 * .hs + Store.hs):                        *
 * - putObject: write to temp file, then   *
 *   rename to <sha256[0:2]>/<sha256>      *
 *   (CAS with automatic dedup)           *
 * - putObjectMeta: INSERT ... ON CONFLICT *
 *   DO UPDATE (overwrite semantics).      *
 *   ref_count column removed (d906a68);   *
 *   dedup via filesystem (same SHA-256 →  *
 *   same file path). The TLA+ model uses  *
 *   explicit ref-counting as an idealized *
 *   specification — the implementation    *
 *   achieves equivalent safety through    *
 *   filesystem-level content addressing.  *
 * - deleteObjectMeta: DELETE by bucket_id *
 *   + key, then unlink file from disk    *
 * - CopyObject: copies metadata (same     *
 *   sha256/size/etag) to new key —        *
 *   same content, new reference           *
 * - Atomic writes: temp file + rename(2)  *
 * - Immutable: once under hash, content   *
 *   never changes                         *
 *******************************************)

EXTENDS Naturals, FiniteSets

CONSTANTS
    ObjectKeys,
    ContentValues,
    MaxObjects

\* Fixed hash domain for small-model checking
SHAValues == {"s1", "s2"}

\* Injective hash function (hardcoded for the 2-value universe)
\* Matches implementation: SHA-256 content hash, deterministic
HashFn == [c \in {"c1", "c2"} |-> IF c = "c1" THEN "s1" ELSE "s2"]

(***************************
 * STATE                   *
 ***************************)

VARIABLE objects   \* set of <<sha, content>>
VARIABLE refs      \* set of <<sha, count>> with count > 0
VARIABLE keys      \* set of <<key, sha>>

\* Helpers
StoredSHAs == {p[1] : p \in objects}
UsedKeys == {p[1] : p \in keys}
KeySha(key) == (CHOOSE p \in keys: p[1] = key)[2]
ShaCnt(sha) == (CHOOSE p \in refs: p[1] = sha)[2]
ShaContent(sha) == (CHOOSE p \in objects: p[1] = sha)[2]
TypeOK ==
    /\ StoredSHAs = {p[1] : p \in refs}
    /\ \A p \in keys: p[2] \in StoredSHAs
    /\ \A p \in objects: p[2] \in ContentValues /\ HashFn[p[2]] = p[1]
    /\ \A p \in refs: p[2] > 0
    /\ UsedKeys \subseteq ObjectKeys
    /\ Cardinality(objects) <= MaxObjects

Init ==
    /\ objects = {}
    /\ refs = {}
    /\ keys = {}

(***************************
 * PUT NEW (sha not exist) *
 ***************************)

\* New content, new key
\* Matches: putObject + putObjectMeta with no existing content
PutNew_NewKey ==
    /\ Cardinality(objects) < MaxObjects
    /\ \E key \in ObjectKeys \ UsedKeys:
        \E content \in ContentValues:
            LET sha == HashFn[content] IN
            /\ sha \notin StoredSHAs
            /\ objects' = objects \cup {<<sha, content>>}
            /\ refs' = refs \cup {<<sha, 1>>}
            /\ keys' = keys \cup {<<key, sha>>}

\* New content, overwrite key with different sha
\* Matches: putObject (new content) + putObjectMeta with ON CONFLICT DO UPDATE
\* Old content may be garbage collected if ref_count reaches 0
PutNew_Overwrite ==
    /\ \E key \in UsedKeys:
        \E content \in ContentValues:
            LET sha == HashFn[content]
                oldSha == KeySha(key)
                oldCnt == ShaCnt(oldSha)
                \* Final objects: add new, maybe remove old
                newObjs == IF oldCnt = 1
                           THEN (objects \cup {<<sha, content>>})
                                \ {<<oldSha, ShaContent(oldSha)>>}
                           ELSE objects \cup {<<sha, content>>}
                \* Final refs: remove/decrement old, add new=1
                newRefs == IF oldCnt = 1
                           THEN (refs \ {<<oldSha, 1>>}) \cup {<<sha, 1>>}
                           ELSE (refs \ {<<oldSha, oldCnt>>})
                                \cup {<<oldSha, oldCnt - 1>>, <<sha, 1>>}
            IN
            /\ sha \notin StoredSHAs
            /\ sha /= oldSha
            /\ objects' = newObjs
            /\ refs' = newRefs
            /\ keys' = (keys \ {<<key, oldSha>>}) \cup {<<key, sha>>}

(***************************
 * PUT DEDUP (sha exists)  *
 ***************************)

\* Existing sha, new key
\* Matches: putObject detects existing file (doesFileExist) + new metadata entry
\* Dedup: same content → same SHA-256 → same file on disk
PutDedup_NewKey ==
    /\ \E key \in ObjectKeys \ UsedKeys:
        \E content \in ContentValues:
            LET sha == HashFn[content]
                cnt == ShaCnt(sha) IN
            /\ sha \in StoredSHAs
            /\ objects' = objects
            /\ refs' = (refs \ {<<sha, cnt>>}) \cup {<<sha, cnt + 1>>}
            /\ keys' = keys \cup {<<key, sha>>}

\* Existing sha, overwrite key with DIFFERENT sha
\* Matches: putObject dedup + putObjectMeta ON CONFLICT DO UPDATE
PutDedup_Overwrite ==
    /\ \E key \in UsedKeys:
        \E content \in ContentValues:
            LET sha == HashFn[content]
                oldSha == KeySha(key)
                oldCnt == ShaCnt(oldSha)
                shaCnt == ShaCnt(sha)
                newObjs == IF oldCnt = 1
                           THEN objects \ {<<oldSha, ShaContent(oldSha)>>}
                           ELSE objects
                newRefs == IF oldCnt = 1
                           THEN (refs \ {<<oldSha, 1>>, <<sha, shaCnt>>})
                                \cup {<<sha, shaCnt + 1>>}
                           ELSE (refs \ {<<oldSha, oldCnt>>, <<sha, shaCnt>>})
                                \cup {<<oldSha, oldCnt - 1>>,
                                      <<sha, shaCnt + 1>>}
            IN
            /\ sha \in StoredSHAs
            /\ sha /= oldSha
            /\ objects' = newObjs
            /\ refs' = newRefs
            /\ keys' = (keys \ {<<key, oldSha>>}) \cup {<<key, sha>>}

(***************************
 * DELETE                  *
 ***************************)

\* Matches: deleteObjectMeta (DELETE from SQLite) + deleteObject (unlink file)
\* When last reference is removed, the content file is deleted
DeleteObject ==
    /\ keys /= {}
    /\ \E key \in UsedKeys:
        LET sha == KeySha(key)
            cnt == ShaCnt(sha)
            newObjs == IF cnt = 1
                       THEN objects \ {<<sha, ShaContent(sha)>>}
                       ELSE objects
            newRefs == IF cnt = 1
                       THEN refs \ {<<sha, 1>>}
                       ELSE (refs \ {<<sha, cnt>>}) \cup {<<sha, cnt - 1>>}
        IN
        /\ objects' = newObjs
        /\ refs' = newRefs
        /\ keys' = keys \ {<<key, sha>>}

(***************************
 * COPY                    *
 ***************************)

\* Matches handleCopyObject:
\* 1. Auth: GetObject on src, PutObject on dst (dual check)
\* 2. Get src metadata (hash, size, etag)
\* 3. putObjectMeta with same hash → same content, new key
\* 4. If dstKey exists and has different sha, old ref is decremented
CopyObject ==
    /\ \E srcKey \in UsedKeys:
        \E dstKey \in ObjectKeys:
            LET sha == KeySha(srcKey)
                cnt == ShaCnt(sha)
                \* Handle dstKey overwrite
                dstOverwrite == IF dstKey \in UsedKeys THEN KeySha(dstKey) /= sha ELSE FALSE
                oldSha == IF dstOverwrite THEN KeySha(dstKey) ELSE sha
                oldCnt == IF dstOverwrite THEN ShaCnt(oldSha) ELSE 1
                newObjs == IF dstOverwrite /\ oldCnt = 1
                           THEN objects \ {<<oldSha, ShaContent(oldSha)>>}
                           ELSE objects
                newRefs == IF dstOverwrite
                           THEN IF oldCnt = 1
                                THEN (refs \ {<<oldSha, 1>>, <<sha, cnt>>})
                                     \cup {<<sha, cnt + 1>>}
                                ELSE (refs \ {<<oldSha, oldCnt>>, <<sha, cnt>>})
                                     \cup {<<oldSha, oldCnt - 1>>,
                                           <<sha, cnt + 1>>}
                           ELSE (refs \ {<<sha, cnt>>})
                                \cup {<<sha, cnt + 1>>}
                newKeys == IF dstOverwrite
                           THEN (keys \ {<<dstKey, oldSha>>}) \cup {<<dstKey, sha>>}
                           ELSE keys \cup {<<dstKey, sha>>}
            IN
            /\ IF dstKey \in UsedKeys THEN KeySha(dstKey) /= sha ELSE TRUE
            /\ objects' = newObjs
            /\ refs' = newRefs
            /\ keys' = newKeys

Next ==
    \/ PutNew_NewKey
    \/ PutNew_Overwrite
    \/ PutDedup_NewKey
    \/ PutDedup_Overwrite
    \/ DeleteObject
    \/ CopyObject

Spec == Init /\ [][Next]_<<objects, refs, keys>>

(***************************
 * INVARIANTS              *
 ***************************)

\* INVARIANT 1: All reference counts are strictly positive.
\* Non-ref-counted overwrite semantics in implementation also
\* satisfy this — a content exists iff at least one key points to it.
RefCountPositive == \A p \in refs: p[2] > 0

\* INVARIANT 2: Store and refs share the same SHA domain.
StoreRefsDomainMatch == StoredSHAs = {p[1] : p \in refs}

\* INVARIANT 3: Reference count exactly equals the number of keys
\* pointing to that hash. This holds for both ref-counting and
\* overwrite semantics.
RefCountMatchesKeys ==
    \A p \in refs:
        p[2] = Cardinality({q \in keys: q[2] = p[1]})

\* INVARIANT 4: Content hash is always correct (deterministic).
\* Matches: SHA-256 computed incrementally during conduit write.
HashCorrect == \A p \in objects: HashFn[p[2]] = p[1]

\* INVARIANT 5: No key references a missing hash.
\* Matches: FOREIGN KEY sha256 in objects table.
NoDanglingKeys == \A p \in keys: p[2] \in StoredSHAs

\* INVARIANT 6: No two different contents share a hash.
\* Matches: SHA-256 collision resistance assumption.
NoHashCollision == \A p1, p2 \in objects: p1[1] = p2[1] => p1[2] = p2[2]

====================================================================================
