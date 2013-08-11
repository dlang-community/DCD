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

(provide 'ac-dcd)
(require 'auto-complete)

(defcustom ac-dcd-executable
  (executable-find "dcd-client")
  "*Location of dcd-client executable"
  :group 'auto-complete
  :type 'file)

;;; Extra compilation flags to pass to dcd.
(defcustom ac-dcd-flags nil
  "Extra flags to pass to the Dcd executable.
This variable will typically contain include paths, e.g., ( \"-I~/MyProject\", \"-I.\" )."
  :group 'auto-complete
  :type '(repeat (string :tag "Argument" "")))

(defconst ac-dcd-completion-pattern
  "^\\(%s[^\s\n]*\\)[ \t]+[cisuvmkfgepM]")

(defconst ac-dcd-error-buffer-name "*dcd error*")

(defun ac-dcd-parse-output (prefix)
  (goto-char (point-min))
  (let ((pattern (format ac-dcd-completion-pattern
                         (regexp-quote prefix)))
        lines match detailed_info
        (prev-match ""))
    (while (re-search-forward pattern nil t)
      (setq match (match-string-no-properties 1))
      (unless (string= "Pattern" match)
        (setq detailed_info (match-string-no-properties 2))
        (if (string= match prev-match)
            (progn
              (when detailed_info
                (setq match (propertize match
                                        'ac-dcd-help
                                        (concat
                                         (get-text-property 0 'ac-dcd-help (car lines))
                                         "\n"
                                         detailed_info)))
                (setf (car lines) match)))
          (setq prev-match match)
          (when detailed_info
            (setq match (propertize match 'ac-dcd-help detailed_info)))
          (push match lines))))
    lines))

(defun ac-dcd-handle-error (res args)
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

(defun ac-dcd-call-process (prefix &rest args)
  (let ((buf (get-buffer-create "*dcd-output*"))
        res)
    (with-current-buffer buf (erase-buffer))
    (setq res (apply 'call-process-region (point-min) (point-max)
		     ac-dcd-executable nil buf nil args))
    (with-current-buffer buf
      (unless (eq 0 res)
        (ac-dcd-handle-error res args))
      ;; Still try to get any useful input.
      (ac-dcd-parse-output prefix))))

(defsubst ac-dcd-build-complete-args (pos)
  (append '()
	  '("-c")
	  (list (format "%s" pos))
  	  ac-dcd-flags))


(defsubst ac-dcd-clean-document (s)
  (when s
    (setq s (replace-regexp-in-string "<#\\|#>\\|\\[#" "" s))
    (setq s (replace-regexp-in-string "#\\]" " " s)))
  s)

(defun ac-dcd-document (item)
  (if (stringp item)
      (let (s)
        (setq s (get-text-property 0 'ac-dcd-help item))
        (ac-dcd-clean-document s))))

(defsubst ac-in-string/comment ()
  "Return non-nil if point is in a literal (a comment or string)."
  (nth 8 (syntax-ppss)))

(defun ac-dcd-candidate ()
  (unless (ac-in-string/comment)
    (save-restriction
      (widen)
      (apply 'ac-dcd-call-process
             ac-prefix
             (ac-dcd-build-complete-args (point))))))

(defvar ac-template-start-point nil)
(defvar ac-template-candidates (list "ok" "no" "yes:)"))

(defun ac-dcd-action ()
  (interactive)
  (let ((help (ac-dcd-clean-document (get-text-property 0 'ac-dcd-help (cdr ac-last-completion))))
        (raw-help (get-text-property 0 'ac-dcd-help (cdr ac-last-completion)))
        (candidates (list)) ss fn args (ret-t "") ret-f)
    (setq ss (split-string raw-help "\n"))
    (dolist (s ss)
      (when (string-match "\\[#\\(.*\\)#\\]" s)
        (setq ret-t (match-string 1 s)))
      (setq s (replace-regexp-in-string "\\[#.*?#\\]" "" s)))
    (cond (candidates
           (setq candidates (delete-dups candidates))
           (setq candidates (nreverse candidates))
           (setq ac-template-candidates candidates)
           (setq ac-template-start-point (point))
           (ac-complete-template)
           (unless (cdr candidates) ;; unless length > 1
             (message (replace-regexp-in-string "\n" "   ;    " help))))
          (t
           (message (replace-regexp-in-string "\n" "   ;    " help))))))

(defun ac-dcd-prefix ()
  (or (ac-prefix-symbol)
      (let ((c (char-before)))
        (when (or (eq ?\. c)
                  (and (eq ?> c)
                       (eq ?- (char-before (1- (point)))))
                  (and (eq ?: c)
                       (eq ?: (char-before (1- (point))))))
          (point)))))

(ac-define-source dcd
  '((candidates . ac-dcd-candidate)
    (prefix . ac-dcd-prefix)
    (requires . 0)
    (document . ac-dcd-document)
    (action . ac-dcd-action)
    (cache)))

(defun ac-dcd-same-count-in-string (c1 c2 s)
  (let ((count 0) (cur 0) (end (length s)) c)
    (while (< cur end)
      (setq c (aref s cur))
      (cond ((eq c1 c)
             (setq count (1+ count)))
            ((eq c2 c)
             (setq count (1- count))))
      (setq cur (1+ cur)))
    (= count 0)))

(defun ac-dcd-split-args (s)
  (let ((sl (split-string s ", *")))
    (cond ((string-match "<\\|(" s)
           (let ((res (list)) (pre "") subs)
             (while sl
               (setq subs (pop sl))
               (unless (string= pre "")
                 (setq subs (concat pre ", " subs))
                 (setq pre ""))
               (cond ((and (ac-dcd-same-count-in-string ?\< ?\> subs)
                           (ac-dcd-same-count-in-string ?\( ?\) subs))
                      (push subs res))
                     (t
                      (setq pre subs))))
             (nreverse res)))
          (t
           sl))))

(defun ac-template-candidate ()
  ac-template-candidates)

(defun ac-template-action ()
  (interactive)
  (unless (null ac-template-start-point)
    (let ((pos (point)) sl (snp "")
          (s (get-text-property 0 'raw-args (cdr ac-last-completion)))))))

(defun ac-template-prefix ()
  ac-template-start-point)


;; this source shall only be used internally.
(ac-define-source template
  '((candidates . ac-template-candidate)
    (prefix . ac-template-prefix)
    (requires . 0)
    (action . ac-template-action)
    (document . ac-dcd-document)
    (cache)
    (symbol . "t")))

;;; auto-complete-dcd.el ends here
