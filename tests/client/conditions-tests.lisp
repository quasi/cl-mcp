;;; tests/client/conditions-tests.lisp
;;; ABOUTME: Tests for cl-mcp/client condition types

(in-package #:cl-mcp-client-tests)

(def-suite client-conditions-tests
  :description "Client condition tests"
  :in cl-mcp-client-tests)

(in-suite client-conditions-tests)

(test mcp-connect-error-has-command-slot
  "mcp-connect-error carries the command that failed"
  (let ((c (make-condition 'cl-mcp.client.conditions:mcp-connect-error
                           :message "failed"
                           :command '("npx" "server-broken"))))
    (is (equal '("npx" "server-broken")
               (cl-mcp.client.conditions:connect-error-command c)))))

(test mcp-session-closed-is-mcp-error
  "mcp-session-closed inherits from mcp-error"
  (is (typep (make-condition 'cl-mcp.client.conditions:mcp-session-closed
                             :message "gone")
             'cl-mcp.conditions:mcp-error)))

(test mcp-tool-error-has-name-and-content
  "mcp-tool-error carries tool name and content from server"
  (let ((c (make-condition 'cl-mcp.client.conditions:mcp-tool-error
                           :message "tool failed"
                           :tool-name "my-tool"
                           :content "Something went wrong")))
    (is (string= "my-tool" (cl-mcp.client.conditions:tool-error-name c)))
    (is (string= "Something went wrong" (cl-mcp.client.conditions:tool-error-content c)))))

(test client-condition-hierarchy
  "All client conditions inherit from mcp-error"
  (is (subtypep 'cl-mcp.client.conditions:mcp-connect-error
                'cl-mcp.conditions:mcp-error))
  (is (subtypep 'cl-mcp.client.conditions:mcp-session-closed
                'cl-mcp.conditions:mcp-error))
  (is (subtypep 'cl-mcp.client.conditions:mcp-tool-error
                'cl-mcp.conditions:mcp-error)))
