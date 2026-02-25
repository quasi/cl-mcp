;;; src/tools.lisp
;;; ABOUTME: MCP tool registry and dispatch

(in-package #:cl-mcp.tools)

;;; Tool Definition Structure

(defstruct (tool-definition (:conc-name tool-))
  "Definition of an MCP tool"
  (name "" :type string)
  (description "" :type string)
  (input-schema nil :type list)
  (handler nil :type (or function null)))

;;; Registry Functions
;;; All take a registry (hash-table) as first argument.
;;; No global state.

(defun register-tool (registry name description input-schema handler)
  "Register a tool in REGISTRY.
HANDLER is a function of (arguments) returning a string or content-block list."
  (check-type handler function)
  (setf (gethash name registry)
        (make-tool-definition
         :name name
         :description description
         :input-schema input-schema
         :handler handler)))

(defun get-tool (registry name)
  "Get a tool definition by NAME from REGISTRY. Returns nil if not found."
  (gethash name registry))

(defun list-tools (registry)
  "Return a list of all tool definitions in REGISTRY."
  (loop for tool being the hash-values of registry
        collect tool))

(defun tools-for-mcp (registry)
  "Format all tools in REGISTRY for MCP tools/list response."
  (loop for tool being the hash-values of registry
        collect `(("name" . ,(tool-name tool))
                  ("description" . ,(tool-description tool))
                  ("inputSchema" . ,(tool-input-schema tool)))))

;;; Argument Validation

(defun validate-tool-args (args schema)
  "Validate ARGS against the tool's input SCHEMA.
Signals INVALID-PARAMS if required arguments are missing."
  (let ((required (cdr (assoc "required" schema :test #'string=))))
    (dolist (req-name required)
      (unless (assoc req-name args :test #'string=)
        (error 'invalid-params
               :message (format nil "Missing required argument: ~a" req-name)))))
  t)

;;; Result Normalization

(defun content-block-list-p (result)
  "Return T if RESULT looks like a list of MCP content blocks.
A content block is an alist with at least a \"type\" key."
  (and (listp result)
       (consp (first result))
       (listp (first result))
       (assoc "type" (first result) :test #'string=)))

(defun normalize-tool-result (result)
  "Normalize a handler result to MCP content format.
If RESULT is a string, wrap in a single text content block.
If RESULT is a list of content blocks, use as-is."
  (cond
    ((stringp result)
     `((("type" . "text") ("text" . ,result))))
    ((content-block-list-p result)
     result)
    (t
     `((("type" . "text") ("text" . ,(princ-to-string result)))))))

;;; Tool Calling

(defun call-tool (registry name args)
  "Call tool NAME with ARGS from REGISTRY.
Signals METHOD-NOT-FOUND if the tool doesn't exist.
Signals INVALID-PARAMS if required arguments are missing.
Returns normalized content blocks."
  (let ((tool (get-tool registry name)))
    (unless tool
      (error 'method-not-found
             :message (format nil "Tool not found: ~a" name)))
    (validate-tool-args args (tool-input-schema tool))
    (let ((result (funcall (tool-handler tool) args)))
      (normalize-tool-result result))))
