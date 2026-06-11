---- MODULE EndpointCoverage ----
(*******************************************
 * Endpoint Coverage and Auth Wiring        *
 * Verifies the contract between Server.hs  *
 * routes and Handler module functions.     *
 *******************************************)

EXTENDS Naturals, FiniteSets

(***************************
 * The 14 S3 actions        *
 ***************************)

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
    "S3AbortMultipartUpload"
}

ReadOnlyActions == {
    "S3GetObject",
    "S3HeadObject",
    "S3ListObjects",
    "S3ListBuckets",
    "S3HeadBucket"
}

(***************************
 * HANDLER DEFINITIONS      *
 * From the Handler modules  *
 ***************************)

HandlerDefs == {
    [name |-> "handleListBuckets",             action |-> "S3ListBuckets",              hasAuth |-> TRUE,  location |-> "Bucket/Handler.hs"],
    [name |-> "handleCreateBucket",            action |-> "S3CreateBucket",             hasAuth |-> TRUE,  location |-> "Bucket/Handler.hs"],
    [name |-> "handleDeleteBucket",            action |-> "S3DeleteBucket",             hasAuth |-> TRUE,  location |-> "Bucket/Handler.hs"],
    [name |-> "handleHeadBucket",              action |-> "S3HeadBucket",               hasAuth |-> TRUE,  location |-> "Bucket/Handler.hs"],
    [name |-> "handlePutObject",               action |-> "S3PutObject",                hasAuth |-> TRUE,  location |-> "Object/Handler.hs"],
    [name |-> "handleGetObject",               action |-> "S3GetObject",                hasAuth |-> TRUE,  location |-> "Object/Handler.hs"],
    [name |-> "handleDeleteObject",            action |-> "S3DeleteObject",             hasAuth |-> TRUE,  location |-> "Object/Handler.hs"],
    [name |-> "handleHeadObject",              action |-> "S3HeadObject",               hasAuth |-> TRUE,  location |-> "Object/Handler.hs"],
    [name |-> "handleCopyObject",              action |-> "S3CopyObject",               hasAuth |-> TRUE,  location |-> "Object/Handler.hs"],
    [name |-> "handleListObjects",             action |-> "S3ListObjects",              hasAuth |-> TRUE,  location |-> "List/Handler.hs"],
    [name |-> "handleCreateMultipartUpload",   action |-> "S3CreateMultipartUpload",    hasAuth |-> TRUE,  location |-> "Multipart/Handler.hs"],
    [name |-> "handleUploadPart",              action |-> "S3UploadPart",               hasAuth |-> TRUE,  location |-> "Multipart/Handler.hs"],
    [name |-> "handleCompleteMultipartUpload", action |-> "S3CompleteMultipartUpload",  hasAuth |-> TRUE,  location |-> "Multipart/Handler.hs"],
    [name |-> "handleAbortMultipartUpload",    action |-> "S3AbortMultipartUpload",     hasAuth |-> TRUE,  location |-> "Multipart/Handler.hs"]
}

(***************************
 * ROUTE TABLE (Server.hs)  *
 * Actual wired routes       *
 ***************************)

RouteTable == {
    [route |-> "GET /",                        handler |-> "handleListBuckets",             inlineAuth |-> TRUE],
    [route |-> "PUT /{bucket}",                handler |-> "handleCreateBucket",            inlineAuth |-> TRUE],
    [route |-> "DELETE /{bucket}",             handler |-> "handleDeleteBucket",            inlineAuth |-> TRUE],
    [route |-> "HEAD /{bucket}",               handler |-> "handleHeadBucket",              inlineAuth |-> TRUE],
    [route |-> "GET /{bucket}",                handler |-> "handleListObjects",             inlineAuth |-> TRUE],
    [route |-> "GET /{bucket}/{key}",          handler |-> "handleGetObject",               inlineAuth |-> TRUE],
    [route |-> "DELETE /{bucket}/{key}",       handler |-> "handleDeleteObject",            inlineAuth |-> TRUE],
    [route |-> "HEAD /{bucket}/{key}",         handler |-> "handleHeadObject",              inlineAuth |-> TRUE],
    [route |-> "POST /{bucket}/{key}?uploads", handler |-> "handleCreateMultipartUpload",   inlineAuth |-> TRUE],
    [route |-> "PUT /{bucket}/{key}?uploadId", handler |-> "handleUploadPart",              inlineAuth |-> TRUE],
    [route |-> "POST /{bucket}/{key}?uploadId",handler |-> "handleCompleteMultipartUpload", inlineAuth |-> TRUE],
    [route |-> "DELETE /{bucket}/{key}?uploadId",handler |-> "handleAbortMultipartUpload",   inlineAuth |-> TRUE],
    [route |-> "PUT /{bucket}/{key}",          handler |-> "handlePutObject",               inlineAuth |-> TRUE],
    [route |-> "PUT /{bucket}/{key} (copy)",   handler |-> "handleCopyObject",              inlineAuth |-> TRUE]
}

(***************************
 * DERIVED SETS             *
 ***************************)

CalledHandlers == { r.handler : r \in RouteTable }
DefinedHandlerNames == { h.name : h \in HandlerDefs }
OrphanedHandlers == DefinedHandlerNames \ CalledHandlers
NonAuthRoutes == { r \in RouteTable : r.inlineAuth = FALSE }

(***************************
 * ASSUME ASSERTIONS        *
 * Verified at parse time    *
 ***************************)

ASSUME HandlerCountCorrect == Cardinality(HandlerDefs) = 14

ASSUME ActionCountCorrect == Cardinality(AllActions) = 14

ASSUME AllActionsHaveHandlers ==
    \A action \in AllActions:
        \E h \in HandlerDefs: h.action = action

ASSUME AllHandlersHaveAuth ==
    \A h \in HandlerDefs: h.hasAuth

ASSUME RouteCountCorrect == Cardinality(RouteTable) = 14

ASSUME AllRoutesAuthorized == Cardinality(NonAuthRoutes) = 0

ASSUME NoOrphanedHandlers == Cardinality(OrphanedHandlers) = 0

ASSUME AllCalledHandlersDefined ==
    \A r \in RouteTable:
        r.handler \in DefinedHandlerNames

ASSUME CopyObjectIsRouted ==
    \E r \in RouteTable: r.handler = "handleCopyObject"

ASSUME PutObjectIsRouted ==
    \E r \in RouteTable: r.handler = "handlePutObject"

(***************************
 * MINIMAL SPEC FOR TLC     *
 ***************************)

VARIABLE dummy
Init == dummy = 0
Next == dummy' = dummy
Spec == Init /\ [][Next]_dummy

====================================================================================
