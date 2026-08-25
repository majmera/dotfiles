(require 'package) ;; You might already have this line
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(dolist (pkg '(company ggtags))
  (unless (package-installed-p pkg)
    (unless package-archive-contents
      (package-refresh-contents))
    (package-install pkg)))

(require 'color-theme-sanityinc-tomorrow)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(c-basic-offset 4 t)
 '(custom-enabled-themes (quote (sanityinc-tomorrow-eighties)))
 '(custom-safe-themes
   (quote
    ("628278136f88aa1a151bb2d6c8a86bf2b7631fbea5f0f76cba2a0079cd910f7d" "c4465c56ee0cac519dd6ab6249c7fd5bb2c7f7f78ba2875d28a50d3c20a59473" "f782ed87369a7d568cee28d14922aa6d639f49dd676124d817dd82c8208985d0" default)))
 '(debug-on-error t)
 '(delete-selection-mode nil)
 '(ecb-options-version "2.40")
 '(indent-tabs-mode nil)
 '(nrepl-message-colors
   (quote
    ("#CC9393" "#DFAF8F" "#F0DFAF" "#7F9F7F" "#BFEBBF" "#93E0E3" "#94BFF3" "#DC8CC3")))
 '(package-selected-packages
   (quote
    (xhair flycheck elpy rainbow-identifiers rainbow-delimiters ggtags evil-search-highlight-persist color-theme-sanityinc-tomorrow color-theme-modern color-theme)))
 '(sr-speedbar-max-width 40)
 '(sr-speedbar-right-side nil))

(setq c-default-style "linux"
      c-basic-offset 4)

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )


;;Disable start up screen
(setq inhibit-startup-message t)

;Disable toolbar
(tool-bar-mode -1)

;;Load theme
(load-theme 'sanityinc-tomorrow-eighties t)

;;Change how selected text appears
(set-face-attribute 'region nil :background "#666" :foreground "#ffffff")

(setq large-file-warning-threshold 50000000)

;;Expand Region
;(require 'expand-region)


(add-hook 'prog-mode-hook #'rainbow-delimiters-mode)

;;; Turn off auto-save and backup
;disable backup
(setq backup-inhibited t)
;disable auto save
(setq auto-save-default nil)

;; Use spaces to indent
;; set indentation to 4 spaces
(setq-default indent-tabs-mode nil)
(setq tab-width 4)

;; Windmove
(when (fboundp 'windmove-default-keybindings)
    (windmove-default-keybindings))

;;(defadvice terminal-init-screen
  ;; The advice is named `tmux', and is run before `terminal-init-screen' runs.
;;  (before tmux activate)
  ;; Docstring.  This describes the advice and is made available inside emacs;
  ;; for example when doing C-h f terminal-init-screen RET
;;  "Apply xterm keymap, allowing use of keys passed through tmux."
  ;; This is the elisp code that is run before `terminal-init-screen'.
;;  (if (getenv "TMUX")
;;    (let ((map (copy-keymap xterm-function-map)))
;;    (set-keymap-parent map (keymap-parent input-decode-map))
;;    (set-keymap-parent input-decode-map map))))


;; Elpy setup for Python IDE
(require 'elpy)
(setq elpy-modules (delq 'elpy-module-flymake elpy-modules))
(elpy-enable)
(require 'flycheck)
(add-hook 'elpy-mode-hook #'flycheck-mode)

;; Make FlyMake default
(defvar myPackages
  '(better-defaults
    elpy
    flycheck ;; add the flycheck package
    material-theme
    company))

(require 'cc-mode)
(require 'company)
(require 'eglot)

(setq company-minimum-prefix-length 1
      company-idle-delay 0.0)

(global-company-mode 1)

(add-to-list 'eglot-server-programs
             '((c-mode c++-mode) . ("clangd"
                                    "--header-insertion=never"
                                    "--completion-style=detailed"
                                    "--clang-tidy")))

(defun my-c/c++-mode-setup ()
  (setq c-basic-offset 4)
  (setq-local company-backends '((company-capf company-dabbrev-code company-keywords company-files)))
  (company-mode 1)
  (when (executable-find "clangd")
    (eglot-ensure))
  (when (require 'ggtags nil t)
    (ggtags-mode 1))
  (when (executable-find "clang-format")
    (local-set-key (kbd "C-c C-f") #'clang-format-buffer)))

(add-hook 'c-mode-hook #'my-c/c++-mode-setup)
(add-hook 'c++-mode-hook #'my-c/c++-mode-setup)

(global-hl-line-mode 1)
(set-face-attribute hl-line-face nil :underline t)

(require 'smerge-mode)
