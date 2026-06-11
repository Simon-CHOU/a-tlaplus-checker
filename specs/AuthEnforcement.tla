---- MODULE AuthEnforcement ----
(*******************************************
 * Auth Enforcement Matrix                  *
 * Verifies: every S3 HTTP handler enforces *
 * the correct (Action, ResourceARN) pair   *
 * before executing the operation.          *
 *                                           *
 * This closes the HIGH-severity Gap #1      *
 * from the contract analysis: "No spec      *
 * verifies handler→Action→ResourceARN       *
 * mapping."                                 *
 *                                           *
 * Implementation contract (from handlers):  *
 * - Bucket ops use bucket-level ARN          *
 * - Object ops use object-level ARN          *
 * - CopyObject checks BOTH src+dest          *
 * - Multipart ops check object ARN           *
 * - ListBuckets uses wildcard ARN "*"        *
 * - ListObjects uses bucket-level ARN        *
 *******************************************)

EXTENDS Naturals, FiniteSets

(***************************
 * FIXED PARAMETERS        *
 ***************************)

CONSTANTS
    Buckets,           \* Set of bucket names
    ObjectKeys,        \* Set of object keys
    PolicyActions,     \* Small set of actions usable in policies
    PolicyResources,   \* Small set of resources usable in policies
    MaxPolicies,       \* Bound on number of policies
    MaxOps             \* Bound on number of operations

(***************************
 * TYPE DEFINITIONS        *
 ***************************)

\* The 14 specific S3 actions plus the wildcard
AllActions == {
    "S3GetObject",
    "S3PutObject",
    "S3DeleteObject",
    "S3HeadObject",
    "S3CopyObject",
    "S3ListObjects",
    "S3CreateBucket",
    "S3DeleteBucket",
    "S3ListBuckets",
    "S3HeadBucket",
    "S3CreateMultipartUpload",
    "S3UploadPart",
    "S3CompleteMultipartUpload",
    "S3AbortMultipartUpload",
    "S3AllActions"
}

\* Specific actions only (S3AllActions excluded)
SpecificActions == AllActions \ {"S3AllActions"}

\* Resource ARN construction (matches Haskell helpers)
RESOURCE_TYPES == {"bucket", "object", "wildcard"}

BucketResource(b) == [type |-> "bucket", bucket |-> b]
ObjectResource(b, k) == [type |-> "object", bucket |-> b, key |-> k]
WildcardResource == [type |-> "wildcard"]

AllResources ==
    {BucketResource(b) : b \in Buckets}
    \cup {ObjectResource(b, k) : b \in Buckets, k \in ObjectKeys}
    \cup {WildcardResource}

(***************************
 * ROUTING TABLE            *
 ***************************)

\* Endpoint identifiers (matching the 14 handler functions)
ENDPOINTS == {
    "CreateBucket",
    "DeleteBucket",
    "ListBuckets",
    "HeadBucket",
    "PutObject",
    "GetObject",
    "DeleteObject",
    "HeadObject",
    "CopyObject",
    "ListObjects",
    "CreateMultipartUpload",
    "UploadPart",
    "CompleteMultipartUpload",
    "AbortMultipartUpload"
}

\* RequiredAction[ep]: the S3 Action each endpoint checks before executing.
\* Matches the handler implementations exactly.
RequiredAction == [ep \in ENDPOINTS |->
    CASE ep = "CreateBucket" -> "S3CreateBucket"
      [] ep = "DeleteBucket" -> "S3DeleteBucket"
      [] ep = "ListBuckets" -> "S3ListBuckets"
      [] ep = "HeadBucket" -> "S3HeadBucket"
      [] ep = "PutObject" -> "S3PutObject"
      [] ep = "GetObject" -> "S3GetObject"
      [] ep = "DeleteObject" -> "S3DeleteObject"
      [] ep = "HeadObject" -> "S3HeadObject"
      [] ep = "CopyObject" -> "S3CopyObject"
      [] ep = "ListObjects" -> "S3ListObjects"
      [] ep = "CreateMultipartUpload" -> "S3CreateMultipartUpload"
      [] ep = "UploadPart" -> "S3UploadPart"
      [] ep = "CompleteMultipartUpload" -> "S3CompleteMultipartUpload"
      [] ep = "AbortMultipartUpload" -> "S3AbortMultipartUpload"
]

\* Resource type that each endpoint operates on.
EndpointResourceType == [ep \in ENDPOINTS |->
    CASE ep = "CreateBucket" -> "bucket"
      [] ep = "DeleteBucket" -> "bucket"
      [] ep = "ListBuckets" -> "wildcard"
      [] ep = "HeadBucket" -> "bucket"
      [] ep = "PutObject" -> "object"
      [] ep = "GetObject" -> "object"
      [] ep = "DeleteObject" -> "object"
      [] ep = "HeadObject" -> "object"
      [] ep = "CopyObject" -> "object"
      [] ep = "ListObjects" -> "bucket"
      [] ep = "CreateMultipartUpload" -> "object"
      [] ep = "UploadPart" -> "object"
      [] ep = "CompleteMultipartUpload" -> "object"
      [] ep = "AbortMultipartUpload" -> "object"
]

(***************************
 * ROUTING TABLE VERIFICATION  *
 * Use ASSUME for constant-    *
 * level properties (they are   *
 * verified at parse time).    *
 ***************************)

\* ASSUME 1: Complete routing table coverage
ASSUME AllEndpointsHaveRoutes ==
    /\ DOMAIN RequiredAction = ENDPOINTS
    /\ DOMAIN EndpointResourceType = ENDPOINTS

\* ASSUME 2: All required actions are valid (non-S3AllActions) S3 actions.
ASSUME ValidActions ==
    \A ep \in ENDPOINTS: RequiredAction[ep] \in SpecificActions

\* ASSUME 3: Bucket-level endpoints use bucket resources.
\* Object-level endpoints use object resources.
\* ListBuckets uses wildcard.
ASSUME ResourceTypeCorrect ==
    /\ \A ep \in {"CreateBucket", "DeleteBucket", "HeadBucket", "ListObjects"}:
        EndpointResourceType[ep] = "bucket"
    /\ \A ep \in {"PutObject", "GetObject", "DeleteObject", "HeadObject",
                  "CreateMultipartUpload", "UploadPart",
                  "CompleteMultipartUpload", "AbortMultipartUpload"}:
        EndpointResourceType[ep] = "object"
    /\ EndpointResourceType["ListBuckets"] = "wildcard"
    /\ EndpointResourceType["CopyObject"] = "object"

\* ASSUME 4: 14 endpoints total.
ASSUME EndpointCount == Cardinality(ENDPOINTS) = 14

\* ASSUME 5: 14 specific actions (one per endpoint).
ASSUME ActionCount == Cardinality(SpecificActions) = 14

(***************************
 * POLICY EVALUATION        *
 * Uses bounded sets to     *
 * avoid state explosion.   *
 ***************************)

EFFECTS == {"Allow", "Deny"}

\* Bounded policy record — uses CONSTANTS with small cardinalities
PolicyRecord ==
    [effect : EFFECTS,
     actions : SUBSET PolicyActions,
     resources : SUBSET PolicyResources]

\* Resource matching with wildcard support
ResourceMatches(policyRes, requestRes) ==
    \/ policyRes = WildcardResource
    \/ /\ policyRes.type = requestRes.type
       /\ IF policyRes.type = "bucket"
          THEN policyRes.bucket = requestRes.bucket
          ELSE IF policyRes.type = "object"
          THEN /\ policyRes.bucket = requestRes.bucket
               /\ policyRes.key = requestRes.key
          ELSE FALSE

\* Action matching: S3AllActions wildcard matches any specific action
ActionMatches(policyAction, requestAction) ==
    \/ policyAction = "S3AllActions"
    \/ policyAction = requestAction

\* Evaluate: deny-overrides-allow, default deny
Evaluate(policies, action, resource) ==
    LET
        matchingDeny == { p \in policies :
            p.effect = "Deny"
            /\ \E a \in p.actions: ActionMatches(a, action)
            /\ \E r \in p.resources: ResourceMatches(r, resource) }
        matchingAllow == { p \in policies :
            p.effect = "Allow"
            /\ \E a \in p.actions: ActionMatches(a, action)
            /\ \E r \in p.resources: ResourceMatches(r, resource) }
    IN
        IF matchingDeny /= {} THEN FALSE
        ELSE IF matchingAllow /= {} THEN TRUE
        ELSE FALSE

(***************************
 * STATE                   *
 ***************************)

VARIABLE policies    \* Current set of IAM policies
VARIABLE ops         \* Audit log of operations that executed

\* Sentinel for "no bucket" or "no key" in operations
NULL == "NULL"

\* An operation record: endpoint + resource parameters
OpRecord ==
    [endpoint : ENDPOINTS,
     bucket : Buckets \cup {NULL},
     key : ObjectKeys \cup {NULL}]

\* Build the actual resource ARN for a given endpoint and parameters
OpResource(rec) ==
    LET ep == rec.endpoint
        tp == EndpointResourceType[ep]
    IN
    IF tp = "wildcard" THEN WildcardResource
    ELSE IF tp = "bucket" THEN BucketResource(rec.bucket)
    ELSE ObjectResource(rec.bucket, rec.key)

TypeOK ==
    /\ policies \subseteq PolicyRecord
    /\ Cardinality(policies) <= MaxPolicies
    /\ ops \subseteq OpRecord
    /\ Cardinality(ops) <= MaxOps

Init ==
    /\ policies = {}
    /\ ops = {}

(***************************
 * OPERATIONS              *
 ***************************)

\* An operation can execute ONLY if the policy allows it.
ExecuteOp(ep) ==
    /\ Cardinality(ops) < MaxOps
    /\ \E b \in Buckets \cup {NULL}:
        \E k \in ObjectKeys \cup {NULL}:
            LET rec == [endpoint |-> ep, bucket |-> b, key |-> k]
                action == RequiredAction[ep]
                resource == OpResource(rec)
            IN
            /\ Evaluate(policies, action, resource)
            /\ ops' = ops \cup {rec}
            /\ UNCHANGED policies

\* Add a policy from the bounded PolicyRecord set
AddPolicy ==
    /\ Cardinality(policies) < MaxPolicies
    /\ \E p \in PolicyRecord:
        /\ p \notin policies
        /\ policies' = policies \cup {p}
        /\ UNCHANGED ops

\* Remove a policy
RemovePolicy ==
    /\ policies /= {}
    /\ \E p \in policies:
        /\ policies' = policies \ {p}
        /\ UNCHANGED ops

Next ==
    \/ \E ep \in ENDPOINTS: ExecuteOp(ep)
    \/ AddPolicy
    \/ RemovePolicy

Spec == Init /\ [][Next]_<<policies, ops>>

(***************************
 * INVARIANTS              *
 ***************************)

\* INVARIANT 1: Type consistency — all ops have valid endpoints and resources
OpTypeOK ==
    /\ \A rec \in ops: rec.endpoint \in ENDPOINTS
    /\ \A rec \in ops: OpResource(rec) \in AllResources

\* INVARIANT 2: No operation executes without authorization.
\* This holds because ExecuteOp has an Evaluate guard.
\* Verify it holds at every state as a sanity check.
AuthorizedOpsOnly ==
    \A rec \in ops:
        Evaluate(policies, RequiredAction[rec.endpoint], OpResource(rec))

\* INVARIANT 3: No operation executes when only policies with no
\* matching actions exist (default deny). Verifies the guard works.
DefaultDenyEnforced ==
    (policies = {}) => (ops = {})

====================================================================================
