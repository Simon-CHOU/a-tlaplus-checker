---- MODULE BucketOps ----
(*******************************************
 * Bucket Lifecycle Operations             *
 * Verifies: non-empty bucket can't be     *
 * deleted, bucket name uniqueness,        *
 * objects only in existing buckets        *
 *******************************************)

EXTENDS Naturals, FiniteSets

CONSTANTS
    BucketNames,     \* Set of all possible bucket names
    ObjectKeys,      \* Set of all possible object keys
    MaxBuckets       \* Bound on number of buckets

(***************************
 * STATE                   *
 ***************************)

VARIABLE buckets       \* Set of existing bucket names
VARIABLE objects       \* Set of <<bucketName, objectKey>> pairs

TypeOK ==
    /\ buckets \subseteq BucketNames
    /\ Cardinality(buckets) <= MaxBuckets
    /\ \A p \in objects: p[1] \in buckets
    /\ \A p \in objects: p[2] \in ObjectKeys

Init ==
    /\ buckets = {}
    /\ objects = {}

(***************************
 * OPERATIONS              *
 ***************************)

\* CreateBucket
CreateBucket ==
    /\ Cardinality(buckets) < MaxBuckets
    /\ \E name \in BucketNames \ buckets:
        /\ buckets' = buckets \cup {name}
        /\ objects' = objects

\* DeleteBucket: only allowed if bucket is empty
DeleteBucket ==
    /\ buckets /= {}
    /\ \E name \in buckets:
        /\ \A p \in objects: p[1] /= name  \* Bucket must be empty
        /\ buckets' = buckets \ {name}
        /\ objects' = objects

\* PutObject: add an object to a bucket
PutObject ==
    /\ buckets /= {}
    /\ \E bucket \in buckets:
        \E key \in ObjectKeys:
            /\ buckets' = buckets
            /\ objects' = objects \cup {<<bucket, key>>}

\* DeleteObject: remove an object from a bucket
DeleteObject ==
    /\ objects /= {}
    /\ \E p \in objects:
        /\ buckets' = buckets
        /\ objects' = objects \ {p}

Next ==
    \/ CreateBucket
    \/ DeleteBucket
    \/ PutObject
    \/ DeleteObject

Spec == Init /\ [][Next]_<<buckets, objects>>

(***************************
 * INVARIANTS              *
 ***************************)

\* All objects belong to existing buckets (no orphans)
NoOrphanObjects ==
    \A p \in objects: p[1] \in buckets

\* Bucket names are unique (inherent in set representation)

====================================================================================
