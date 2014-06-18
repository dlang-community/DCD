#EMACS Integration

##Requirements
* You must have the [auto-complete](https://github.com/auto-complete/auto-complete) package.
* Make sure dcd-client and dcd-server is in your exec-path. Otherwise, please set the variable ```dcd-exectutable``` and ```dcd-server-executable``` using ```M-x customize```.

## Setup
* First, follow the Setup section in the root README.
* Second, add the following to your .emacs. With this setting, dcd-server starts automatically when you open file in d-mode.

(add-to-list 'load-path "path_to_ac-dcd.el")
(require 'ac-dcd)
(add-to-list 'ac-modes 'd-mode)
(defun ac-d-mode-setup ()
  (ac-dcd-maybe-start-server)
  (add-to-list 'ac-sources 'ac-source-dcd)
  (auto-complete-mode t))
(add-hook 'd-mode-hook 'ac-d-mode-setup)

* Third, set import path using ```M-x customize-variable RET ac-dcd-flags```.
* When something is wrong, please check variables with ```M-x customize-apropos RET ac-dcd``` and restart server with ```M-x ac-dcd-init-server```.

## TODO
* better error detection
* detailed ac-source symbol
* goto definition
* show doc
* and so on...