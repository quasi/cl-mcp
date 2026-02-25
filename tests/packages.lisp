;;; tests/packages.lisp
;;; ABOUTME: Test package definitions for cl-mcp

(defpackage #:cl-mcp-tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cl-mcp-tests)

(def-suite cl-mcp-tests
  :description "All tests for cl-mcp")

(defun run-tests ()
  "Run all cl-mcp tests."
  (run! 'cl-mcp-tests))
