;;; xhair-autoloads.el --- automatically extracted autoloads
;;
;;; Code:

(add-to-list 'load-path (directory-file-name
                         (or (file-name-directory #$) (car load-path))))


;;;### (autoloads nil "xhair" "xhair.el" (0 0 0 0))
;;; Generated autoloads from xhair.el

(autoload 'xhair-mode "xhair" "\
Toggle highlighting the current line and column.

This function is the 'easiest' to use if you want to manually
toggle the mode. The parallel function `xhair' defaults to
highlight until the next keypress. The parallel function
`xhair-flash' defaults to highlight for
`xhair-flash-interval' seconds.

This function, when called interactively with a prefix-ARG, if
ARG is a positive integer performs the equivalent of function
`xhair-flash'. For other values of ARG highlights until the
next keypress.

Non-interactively, this function turns highlighting on if ARG is
NIL or positive; otherwise turns it off. When
ONLY-UNTIL-NEXT-EVENT is non-nil, highlighting is turned off at
the next key event. Otherwise, if SECONDS is a number,
highlighting remains on for the maximum of one or SECONDS
seconds. If SECONDS is otherwise non-nil, highlighting remains on
for the maximum of one or variable `xhair-flash-interval'
seconds.

\(fn &optional ARG ONLY-UNTIL-NEXT-EVENT SECONDS)" t nil)

(autoload 'xhair-flash "xhair" "\
Highlight the current line and column briefly.
Defaults to `xhair-flash-interval' seconds or to a numeric
prefix arg SECONDS greater than one second.

\(fn &optional SECONDS)" t nil)

(autoload 'xhair "xhair" "\
Toggle highlighting current position with xhairs.

This function is the 'easiest' to use if you only want
highlighting until the next keypress. The parallel function
`xhair-mode' defaults to highlight until manually toggled.
The parallel function `xhair-flash' defaults to highlight for
`xhair-flash-interval' seconds.

This function, with a non-nil prefix ARG, retains highlighting
until you manually toggle it off.

\(fn &optional ARG)" t nil)

(if (fboundp 'register-definition-prefixes) (register-definition-prefixes "xhair" '("xhair-")))

;;;***

;; Local Variables:
;; version-control: never
;; no-byte-compile: t
;; no-update-autoloads: t
;; coding: utf-8
;; End:
;;; xhair-autoloads.el ends here
