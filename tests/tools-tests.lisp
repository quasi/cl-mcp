;;; tests/tools-tests.lisp
;;; ABOUTME: Tests for tool registry and dispatch

(in-package #:cl-mcp-tests)

(def-suite tools-tests
  :description "Tool registry tests"
  :in cl-mcp-tests)

(in-suite tools-tests)

;;; Registry tests

(test register-and-get-tool
  "Register a tool and retrieve it"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "echo" "Echo input"
                                 '(("type" . "object")
                                   ("required" . ("text"))
                                   ("properties" . (("text" . (("type" . "string"))))))
                                 (lambda (args)
                                   (cdr (assoc "text" args :test #'string=))))
    (let ((tool (cl-mcp.tools:get-tool registry "echo")))
      (is (not (null tool)))
      (is (string= "echo" (cl-mcp.tools:tool-name tool)))
      (is (string= "Echo input" (cl-mcp.tools:tool-description tool))))))

(test get-tool-unknown-returns-nil
  "Unknown tool returns nil"
  (let ((registry (make-hash-table :test #'equal)))
    (is (null (cl-mcp.tools:get-tool registry "nonexistent")))))

(test list-tools-returns-all
  "List all registered tools"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "a" "Tool A" nil (lambda (args) (declare (ignore args)) "a"))
    (cl-mcp.tools:register-tool registry "b" "Tool B" nil (lambda (args) (declare (ignore args)) "b"))
    (is (= 2 (length (cl-mcp.tools:list-tools registry))))))

(test tools-for-mcp-format
  "tools-for-mcp returns correct alist format"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "echo" "Echo" '(("type" . "object")) (lambda (args) (declare (ignore args)) ""))
    (let ((mcp-tools (cl-mcp.tools:tools-for-mcp registry)))
      (is (= 1 (length mcp-tools)))
      (let ((tool (first mcp-tools)))
        (is (string= "echo" (cdr (assoc "name" tool :test #'string=))))
        (is (string= "Echo" (cdr (assoc "description" tool :test #'string=))))
        (is (assoc "inputSchema" tool :test #'string=))))))

;;; Validation tests

(test validate-args-passes-when-present
  "Validation passes when required args are present"
  (is (cl-mcp.tools:validate-tool-args
       '(("code" . "(+ 1 2)"))
       '(("type" . "object") ("required" . ("code"))))))

(test validate-args-signals-on-missing
  "Validation signals invalid-params for missing required args"
  (signals cl-mcp.conditions:invalid-params
    (cl-mcp.tools:validate-tool-args
     '()
     '(("type" . "object") ("required" . ("code"))))))

;;; Call tests

(test call-tool-dispatches-to-handler
  "call-tool dispatches to registered handler"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "echo" "Echo"
                                 '(("type" . "object")
                                   ("required" . ("text"))
                                   ("properties" . (("text" . (("type" . "string"))))))
                                 (lambda (args)
                                   (cdr (assoc "text" args :test #'string=))))
    (let ((result (cl-mcp.tools:call-tool registry "echo" '(("text" . "hello")))))
      ;; String result gets normalized to content blocks
      (is (listp result))
      (is (string= "text" (cdr (assoc "type" (first result) :test #'string=))))
      (is (string= "hello" (cdr (assoc "text" (first result) :test #'string=)))))))

(test call-tool-unknown-signals-error
  "call-tool signals method-not-found for unknown tool"
  (let ((registry (make-hash-table :test #'equal)))
    (signals cl-mcp.conditions:method-not-found
      (cl-mcp.tools:call-tool registry "nonexistent" nil))))

(test call-tool-missing-args-signals-error
  "call-tool signals invalid-params for missing required args"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "echo" "Echo"
                                 '(("type" . "object") ("required" . ("text")))
                                 (lambda (args) (declare (ignore args)) ""))
    (signals cl-mcp.conditions:invalid-params
      (cl-mcp.tools:call-tool registry "echo" nil))))

;;; Result normalization tests

(test result-string-normalized-to-content-block
  "String result becomes a text content block"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "test" "Test" nil
                                 (lambda (args) (declare (ignore args)) "hello world"))
    (let ((result (cl-mcp.tools:call-tool registry "test" nil)))
      (is (= 1 (length result)))
      (is (string= "text" (cdr (assoc "type" (first result) :test #'string=))))
      (is (string= "hello world" (cdr (assoc "text" (first result) :test #'string=)))))))

(test result-content-blocks-passed-through
  "Content block list is passed through directly"
  (let ((registry (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool registry "test" "Test" nil
                                 (lambda (args)
                                   (declare (ignore args))
                                   '((("type" . "text") ("text" . "first"))
                                     (("type" . "text") ("text" . "second")))))
    (let ((result (cl-mcp.tools:call-tool registry "test" nil)))
      (is (= 2 (length result)))
      (is (string= "first" (cdr (assoc "text" (first result) :test #'string=))))
      (is (string= "second" (cdr (assoc "text" (second result) :test #'string=)))))))

;;; Per-server isolation test

(test registries-are-independent
  "Tools registered in one registry don't appear in another"
  (let ((reg-a (make-hash-table :test #'equal))
        (reg-b (make-hash-table :test #'equal)))
    (cl-mcp.tools:register-tool reg-a "only-in-a" "A" nil (lambda (args) (declare (ignore args)) ""))
    (is (not (null (cl-mcp.tools:get-tool reg-a "only-in-a"))))
    (is (null (cl-mcp.tools:get-tool reg-b "only-in-a")))))
