# Emacs Integration

## Requirements

* You must have the
[auto-complete](https://github.com/auto-complete/auto-complete) package. Also,
[yasnippet](https://github.com/capitaomorte/yasnippet) and
[popwin](https://github.com/m2ym/popwin-el) are recommended.
* Make sure `dcd-client` and `dcd-server` are in your exec-path. Otherwise,
  please set the variables `dcd-exectutable` and `dcd-server-executable` using
  `M-x customize`.

## Setup

* Follow the Setup section in the root README.
* Add the following to your .emacs. With this setting, dcd-server starts
  automatically when you open file in d-mode. (Of course, you should edit
  `path_to_ac-dcd.el` to suit your environment.)

        ;;; ac-dcd
        (add-to-list 'load-path "path_to_ac-dcd.el")
        (require 'ac-dcd)

        (add-hook 'd-mode-hook
                  '(lambda () "set up ac-dcd"
                     (auto-complete-mode t)
                     (yas-minor-mode-on)
                     (ac-dcd-maybe-start-server)
                     (add-to-list 'ac-sources 'ac-source-dcd)))

        (define-key d-mode-map (kbd "C-c ?") 'ac-dcd-show-ddoc-with-buffer)
        (define-key d-mode-map (kbd "C-c .") 'ac-dcd-goto-definition)
        (define-key d-mode-map (kbd "C-c ,") 'ac-dcd-goto-def-pop-marker)

        (when (featurep 'popwin)
          (add-to-list 'popwin:special-display-config
                       `(,ac-dcd-error-buffer-name :noselect t))
          (add-to-list 'popwin:special-display-config
                         `(,ac-dcd-document-buffer-name :position right :width 80)))

* You can set import paths using `M-x customize-variable RET ac-dcd-flags`.
* Alternatively, if you're using [DUB](http://code.dlang.org/) to manage your
  project, you can use `M-x ac-dcd-add-imports` to add import paths of the
  current project automatically.
* When something is wrong, please, check variables with `M-x customize-apropos
  RET ac-dcd` and restart server with `M-x ac-dcd-init-server`.

## Features

* Dlang source for auto-complete
* Function calltip expansion with yasnippet
* Show ddoc with `C-c ?`
* Goto definition with `C-c .`
* After goto definition, you can pop to previous position with `C-c ,`

## TODO

* UTF-8 support is in place. However, UTF-16 and UTF-32 may not work correctly.
  (Need help!)
