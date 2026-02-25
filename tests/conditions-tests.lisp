;;; tests/conditions-tests.lisp
;;; ABOUTME: Tests for JSON-RPC condition types

(in-package #:cl-mcp-tests)

(def-suite conditions-tests
  :description "Condition type tests"
  :in cl-mcp-tests)

(in-suite conditions-tests)

(test json-rpc-error-codes
  "JSON-RPC error conditions have correct codes"
  (is (= -32700 (cl-mcp.conditions:error-code
                  (make-condition 'cl-mcp.conditions:parse-error))))
  (is (= -32600 (cl-mcp.conditions:error-code
                  (make-condition 'cl-mcp.conditions:invalid-request))))
  (is (= -32601 (cl-mcp.conditions:error-code
                  (make-condition 'cl-mcp.conditions:method-not-found))))
  (is (= -32602 (cl-mcp.conditions:error-code
                  (make-condition 'cl-mcp.conditions:invalid-params))))
  (is (= -32603 (cl-mcp.conditions:error-code
                  (make-condition 'cl-mcp.conditions:internal-error)))))

(test json-rpc-error-messages
  "JSON-RPC error conditions have messages"
  (let ((err (make-condition 'cl-mcp.conditions:method-not-found
                             :message "Method foo not found")))
    (is (string= "Method foo not found"
                 (cl-mcp.conditions:error-message err)))))

(test condition-hierarchy
  "Conditions have correct inheritance"
  (is (typep (make-condition 'cl-mcp.conditions:parse-error)
             'cl-mcp.conditions:json-rpc-error))
  (is (typep (make-condition 'cl-mcp.conditions:json-rpc-error)
             'cl-mcp.conditions:mcp-error))
  (is (typep (make-condition 'cl-mcp.conditions:mcp-error)
             'error)))
