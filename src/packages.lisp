;;; src/packages.lisp
;;; ABOUTME: Package definitions for cl-mcp

(defpackage #:cl-mcp.conditions
  (:use #:cl)
  (:shadow #:parse-error)
  (:export
   ;; Condition types
   #:mcp-error
   #:json-rpc-error
   #:parse-error
   #:invalid-request
   #:method-not-found
   #:invalid-params
   #:internal-error
   ;; Condition accessors
   #:error-code
   #:error-message
   #:error-data))

(defpackage #:cl-mcp.json-rpc
  (:use #:cl #:cl-mcp.conditions)
  (:shadowing-import-from #:cl-mcp.conditions #:parse-error)
  (:export
   ;; Message types
   #:json-rpc-request
   #:json-rpc-response
   ;; Accessors
   #:request-id
   #:request-method
   #:request-params
   #:response-id
   #:response-result
   #:response-error
   ;; Constructors
   #:make-request
   #:make-notification
   #:notification-p
   #:make-success-response
   #:make-error-response
   ;; Functions
   #:parse-message
   #:encode-response
   #:encode-error
   ;; Utilities
   #:convert-for-json
   #:json-object-p))

(defpackage #:cl-mcp.transport
  (:use #:cl #:cl-mcp.json-rpc)
  (:export
   #:read-message
   #:write-message
   #:with-stdio-transport))

(defpackage #:cl-mcp.tools
  (:use #:cl #:cl-mcp.conditions)
  (:shadowing-import-from #:cl-mcp.conditions #:parse-error)
  (:export
   ;; Tool definition
   #:tool-definition
   #:tool-name
   #:tool-description
   #:tool-input-schema
   #:tool-handler
   #:make-tool-definition
   ;; Registry functions (all take registry as first arg)
   #:register-tool
   #:get-tool
   #:list-tools
   #:tools-for-mcp
   #:call-tool
   #:validate-tool-args
   ;; Result normalization
   #:normalize-tool-result
   #:content-block-list-p))

(defpackage #:cl-mcp
  (:use #:cl
        #:cl-mcp.conditions
        #:cl-mcp.json-rpc
        #:cl-mcp.transport)
  (:shadowing-import-from #:cl-mcp.conditions #:parse-error)
  (:export
   ;; Server
   #:mcp-server
   #:make-server
   #:mcp-server-name
   #:mcp-server-version
   #:mcp-server-protocol-version
   #:mcp-server-tools
   ;; Public API
   #:register-tool
   #:run-server
   ;; Re-export conditions for consumer convenience
   #:mcp-error
   #:json-rpc-error
   #:parse-error
   #:invalid-request
   #:method-not-found
   #:invalid-params
   #:internal-error
   #:error-code
   #:error-message
   #:error-data))
