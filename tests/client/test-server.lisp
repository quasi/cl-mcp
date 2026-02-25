;;; tests/client/test-server.lisp
;;; ABOUTME: Minimal MCP server script for client integration tests.
;;; Not a test file. Invoked as a subprocess by client-tests.lisp.
;;;
;;; Usage: sbcl --non-interactive --load <cl-mcp.asd path> --load <this file>
;;;
;;; Registers two tools:
;;;   echo  -- returns its "msg" argument
;;;   fail  -- returns isError:true with an error message

(handler-case
    (progn
      (require :asdf)
      (asdf:load-system :cl-mcp :verbose nil))
  (error (e)
    (format *error-output* "test-server: failed to load cl-mcp: ~a~%" e)
    (uiop:quit 1)))

(let ((server (cl-mcp:make-server :name "test-server" :version "1.0.0")))

  (cl-mcp:register-tool server "echo"
    :description "Echo the msg argument"
    :schema '(("type" . "object")
              ("required" . ("msg"))
              ("properties" . (("msg" . (("type" . "string")
                                         ("description" . "Message to echo"))))))
    :handler (lambda (args)
               (or (cdr (assoc "msg" args :test #'string=)) "")))

  (cl-mcp:register-tool server "fail"
    :description "Always returns an error result"
    :schema '(("type" . "object"))
    :handler (lambda (args)
               (declare (ignore args))
               ;; Return a content block list with isError implicitly via
               ;; signalling a condition that server turns into error response.
               ;; Actually: return a string; the test checks isError via
               ;; the mcp-tool-error condition in the client.
               ;; We signal an error to produce isError:true in the result.
               (error "intentional tool failure")))

  (cl-mcp:run-server server))
