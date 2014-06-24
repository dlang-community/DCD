;;; ac-dcd.el --- Auto Completion source for dcd for GNU Emacs

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:
;;
;; Auto Completion source for dcd. This code was modified from ac-dscanner.el,
;; which originally came from auto-complete-clang-async.el

;;; Code:

(require 'auto-complete)
(require 'rx)
(require 'yasnippet)

(defcustom ac-dcd-executable
  "dcd-client"
  "Location of dcd-client executable."
  :group 'auto-complete
  :type 'file)

(defcustom ac-dcd-flags nil
  "Extra flags to pass to the dcd-server.
This variable will typically contain include paths,
e.g., (\"-I~/MyProject\", \"-I.\").
You can't put port number flag here.  Set `ac-dcd-server-port' instead."
  :group 'auto-complete
  :type '(repeat (string :tag "Argument" "")))

(defconst ac-dcd-completion-pattern
  "^\\(%s[^\s\n]*\\)[ \t]+\\([cisuvmkfgepM]\\)"
  "Regex to parse dcd output.
\\1 is candidate itself, \\2 is kind of candidate.")

(defconst ac-dcd-error-buffer-name "*dcd error*")

(defcustom ac-dcd-server-executable
  "dcd-server"
  "Location of dcd-server executable."
  :group 'auto-complete
  :type 'file)

(defcustom ac-dcd-server-port 9166
  "Port number of dcd-server.  default is 9166."
  :group 'auto-complete)

(defvar ac-dcd-delay-after-kill-process 200
  "Duration after killing server process in milli second.")


;;server handle functions

(defun ac-dcd-stop-server ()
  "Stop dcd-server manually.  Ordinary, you don't have to call it.
If you want to restart server, use `ac-dcd-init-server' instead."
  (interactive)
  (interrupt-process "dcd-server"))

(defsubst ac-dcd-start-server ()
  "Start dcd-server."
  (let ((buf (get-buffer-create "*dcd-server*")))
	(with-current-buffer buf (start-process "dcd-server" (current-buffer)
											ac-dcd-server-executable 
											(mapconcat 'identity ac-dcd-flags " ")
											"-p"
											(format "%s" ac-dcd-server-port)
											))))

(defun ac-dcd-maybe-start-server ()
  "Start dcd-server.  When the server process is already running, do nothing."
  (unless (get-process "dcd-server")
	(ac-dcd-start-server)))

(defun ac-dcd-init-server ()
  "Start dcd-server.  When the server process is already running, restart it."
  (interactive)
  (when (get-process "dcd-server")
	(ac-dcd-stop-server)
	(sleep-for 0 ac-dcd-delay-after-kill-process))
  (ac-dcd-start-server))


;; output parser functions

(defun ac-dcd-parse-output (prefix)
  "Parse dcd output."
  (goto-char (point-min))
  (let ((pattern (format ac-dcd-completion-pattern
                         (regexp-quote prefix)))
        lines match detailed-info
        (prev-match ""))
    (while (re-search-forward pattern nil t)
      (setq match (match-string-no-properties 1))
      (unless (string= "Pattern" match)
        (setq detailed-info (match-string-no-properties 2))
        (if (string= match prev-match)
            (progn
              (when detailed-info
                (setq match (propertize match
                                        'ac-dcd-help
                                        (concat
                                         (get-text-property 0 'ac-dcd-help (car lines))
                                         "\n"
                                         detailed-info)))
                (setf (car lines) match)))
          (setq prev-match match)
          (when detailed-info
            (setq match (propertize match 'ac-dcd-help detailed-info)))
          (push match lines))))
    lines))

(defun ac-dcd-handle-error (res args)
  "Notify error on parse failure."
  (goto-char (point-min))
  (let* ((buf (get-buffer-create ac-dcd-error-buffer-name))
         (cmd (concat ac-dcd-executable " " (mapconcat 'identity args " ")))
         (pattern (format ac-dcd-completion-pattern ""))
         (err (if (re-search-forward pattern nil t)
                  (buffer-substring-no-properties (point-min)
                                                  (1- (match-beginning 0)))
                ;; Warn the user more agressively if no match was found.
                (message "dcd-client failed with error %d:\n%s" res cmd)
                (buffer-string))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (current-time-string)
                (format "\ndcd-client failed with error %d:\n" res)
                cmd "\n\n")
        (insert err)
        (setq buffer-read-only t)
        (goto-char (point-min))))))


;; utility functions to call process

(defun ac-dcd-call-process (prefix args)
  (let ((buf (get-buffer-create "*dcd-output*"))
        res)
    (with-current-buffer buf (erase-buffer))
    (setq res (apply 'call-process-region (point-min) (point-max)
					 ac-dcd-executable nil buf nil
					 args
					 ))
    (with-current-buffer buf
      (unless (eq 0 res)
        (ac-dcd-handle-error res args))
      ;; Still try to get any useful input.
      (ac-dcd-parse-output prefix))))

(defsubst ac-dcd-cursor-position ()
  "Get cursor position to pass to dcd-client.
TODO: multi byte character support"
  (point))

(defsubst ac-dcd-build-complete-args (pos)
  (list
   "-c"
   (format "%s" pos)
   "-p"
   (format "%s" ac-dcd-server-port)
   ))


(defsubst ac-in-string/comment ()
  "Return non-nil if point is in a literal (a comment or string)."
  (nth 8 (syntax-ppss)))


;; interface to communicate with auto-complete.el

(defun ac-dcd-candidate ()
  (unless (ac-in-string/comment)
    (save-restriction
      (widen)
      (ac-dcd-call-process
	   ac-prefix
	   (ac-dcd-build-complete-args (ac-dcd-cursor-position))))))

(defun ac-dcd-prefix ()
  (or (ac-prefix-symbol)
      (let ((c (char-before)))
        (when (or (eq ?\. c)
                  (and (eq ?> c)
                       (eq ?- (char-before (1- (point)))))
                  (and (eq ?: c)
                       (eq ?: (char-before (1- (point))))))
          (point)))))

(defun ac-dcd-document (item)
  "Return popup document of `ITEM'."
  (if (stringp item)
      (let (s)
        (setq s (get-text-property 0 'ac-dcd-help item))
		(cond
		 ((equal s "c") "class")
		 ((equal s "i") "interface")
		 ((equal s "s") "struct")
		 ((equal s "u") "union")
		 ((equal s "v") "variable")
		 ((equal s "m") "member variable")
		 ((equal s "k") "keyword")
		 ((equal s "f") "function")
		 ((equal s "g") "enum")
		 ((equal s "e") "enum member")
		 ((equal s "P") "package")
		 ((equal s "M") "module")
		 ((equal s "a") "array")
		 ((equal s "A") "associative array")
		 ((equal s "l") "alias")
		 ((equal s "t") "template")
		 ((equal s "T") "mixin template")
		 (t (format "candidate kind undetected: %s" s))
		 ))))


(defun ac-dcd-action ()
  "Try function calltip expansion."
  (when (featurep 'yasnippet)

	(let ((lastcompl (cdr ac-last-completion)))
	  (cond
	   ((equal (get-text-property 0 'ac-dcd-help lastcompl) "f") ; when it was a function
		(progn
		  (insert "(") ;dcd-client requires open parenthesis to complete calltip.
		  (ac-complete-dcd-calltips)))
	   (t nil)
	   ))))

(ac-define-source dcd
  '((candidates . ac-dcd-candidate)
    (prefix . ac-dcd-prefix)
    (requires . 0)
    (document . ac-dcd-document)
	(action . ac-dcd-action)
    (cache)
	(symbol . "D")
	))


;; function calltip expansion with yasnippet

(defun ac-dcd-calltip-candidate ()
  "Do calltip completion of the D symbol at point.
The cursor must be at the end of a D symbol.
When the symbol is not a function, returns nothing"
  (let ((buf (get-buffer-create "*dcd-output*")))
	(ac-dcd-call-process-for-calltips)
	(with-current-buffer buf (ac-dcd-parse-calltips))
	))

(defun ac-dcd-call-process-for-calltips ()
  "Call process to get calltips of the function at point."
  (ac-dcd-call-process
   (concat (cdr ac-last-completion) "(")
   (ac-dcd-build-complete-args (ac-dcd-cursor-position))))


(defconst ac-dcd-calltip-pattern
  (rx bol (submatch (* nonl)) (submatch "(" (* nonl) ")") eol)
  "Regexp to parse calltip completion output.
\\1 is function return type (if exists) and name, and \\2 is args.")

(defsubst ac-dcd-remove-function-return-type (s)
  "Remove return type of function."
  (let ((sl (split-string s)))
	(if (string-match "(" (car sl)) ; filter calltip candidate which has no return type. e.g. std.regex.match
		s
	  (mapconcat 'identity (cdr sl) " ")
	  )))


(defun ac-dcd-parse-calltips ()
  "Parse dcd output for calltips completion.
It returns a list of calltip candidates."
  (goto-char (point-min))
  (let ((pattern ac-dcd-calltip-pattern)
		lines
		match
		(prev-match ""))
	(while (re-search-forward pattern nil t)
	  (setq match (ac-dcd-remove-function-return-type (concat (match-string-no-properties 1) (match-string-no-properties 2))))
	  (push match lines))
	lines
	))

(defun ac-dcd-calltip-action ()
  "Format the calltip to yasnippet style.
This function should be called at *dcd-output* buf."
  (let (beg end)
	(save-excursion	
	  (setq end (point))
	  (setq beg (progn
				  ;; find the end of function name. some function arguments have parenthesis of its own,
				  ;; so I had to do it like this.
				  (search-backward (cdr ac-last-completion))
				  (-  (search-forward "(" ) 1)))
	  (kill-region beg end))
	(let ((str (car kill-ring))
		  yasstr)
	  (setq kill-ring (cdr kill-ring)); clean up kill-ring

	  ;remove parenthesis
	  (setq str (substring str 1 (- (length str) 1)))
	  
	  (setq yasstr
			(mapconcat
			 (lambda (s) "format each args to yasnippet style" (concat "${" s "}"))
			 (split-string str ", ")
			 ", "))
	  (setq yasstr (concat "(" yasstr ")"))
	  ;; ;;debug
	  ;; (message (format "str: %s" str))
	  ;; (message (format "yasstr: %s" yasstr))
	  (yas-expand-snippet yasstr))))

(defun ac-dcd-calltip-prefix ()
  (car ac-last-completion))

(ac-define-source dcd-calltips
  '((candidates . ac-dcd-calltip-candidate)
	(prefix . ac-dcd-calltip-prefix)
	(action . ac-dcd-calltip-action)
	(cache)
	))


;;show document

(defun ac-dcd-get-ddoc (pos)
  "Get document with `dcd-client --doc'.  `POS' is cursor position.
TODO:reformat it."
  (let ((args 
		 (append
		  (ac-dcd-build-complete-args (ac-dcd-cursor-position))
		  '("--doc")
		  (list (buffer-file-name))))
		(buf (get-buffer-create "*dcd-output*")))
	(with-current-buffer
		buf (erase-buffer)
		(apply 'call-process ac-dcd-executable nil buf nil args))
	(let ((raw-doc (with-current-buffer buf (buffer-string))))
	  ;; ;; TODO: format document string. 
	  ;; (setq raw-doc (replace-regexp-in-string
	  ;; 				 (rx (and (not (any "\\\\")) (submatch "\\n")))
	  ;; 				 " " raw-doc  nil nil 1 nil)); replace \n with space
	  ;; ;; (setq raw-doc (replace-regexp-in-string
	  ;; ;; 				 (rx "\\n") "\n" raw-doc));replace \\n(RET in D src) with \n
	  ;; (setq raw-doc (replace-regexp-in-string
	  ;; 				 (rx (and "$(D" (submatch (* anything)) ")"))
	  ;; 				 " `\\1' " raw-doc)) ;format D src
	  raw-doc)))

(defun ac-dcd-popup-ddoc-at-point ()
  "Popup Ddoc at point using popup.el."
  (interactive)
  (let ((doc (ac-dcd-get-ddoc (ac-dcd-cursor-position))))
	(when (or(string= doc "")
			 (string= doc "\n\n\n") ;when symbol has no doc
			 )
	  (message "No document for the symbol at point!"))))



(provide 'ac-dcd)
;;; ac-dcd.el ends here
