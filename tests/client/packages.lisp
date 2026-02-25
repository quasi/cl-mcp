;;; tests/client/packages.lisp
;;; ABOUTME: Test package definitions for cl-mcp/client

(defpackage #:cl-mcp-client-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cl-mcp-client-tests)

(def-suite cl-mcp-client-tests
  :description "All tests for cl-mcp/client")

(defun run-tests ()
  "Run all cl-mcp/client tests."
  (run! 'cl-mcp-client-tests))
