;; -*- elisp -*-

;; Fail fast in CI
(setq debug-on-error t
      noninteractive t
      inhibit-message t)

;; Keep all state local to the project (cache this dir in CI)
(defvar my/project-root (file-name-directory (or load-file-name default-directory)))
(setq user-emacs-directory (expand-file-name ".emacs.cache.d/" my/project-root))
(setq package-user-dir      (expand-file-name "elpa/" user-emacs-directory))
(make-directory package-user-dir t)

;; Package setup
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
;; If GPG keys are an issue in CI, either import them or temporarily disable:
;; (setq package-check-signature nil)

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(add-to-list 'package-pinned-packages '(citeproc . "melpa"))

(dolist (pkg '(org org-contrib htmlize citeproc))    
  (unless (package-installed-p pkg)
    (package-install pkg)))


(require 'ox-publish)
(require 'ox-latex)
(require 'ox-html)
(require 'json)
(require 'htmlize nil t)
(use-package citeproc :ensure t :pin melpa) 
(require 'oc-csl)

(setq org-export-babel-evaluate t
      org-confirm-babel-evaluate nil)
(org-babel-do-load-languages 'org-babel-load-languages '((emacs-lisp . t)))

(setq org-cite-csl-styles-dir  "content")
;;       org-cite-csl-locales-dir "content")  ;; needs en-US at least

(setq org-html-doctype "html5"
      org-html-html5-fancy t
      org-html-validation-link nil
      org-html-head-include-default-style nil
      org-html-head-include-scripts nil
      org-export-with-broken-links 'mark
      org-html-htmlize-output-type 'css ;; Code highlighting (pure CSS; requires htmlize)
      org-html-with-latex 'dvisvgm       ;; LaTeX math -> SVG images (no MathJax/JS)
      org-latex-create-formula-image-program 'dvisvgm
      ;;
      org-export-with-toc nil
      org-export-with-date t
      org-export-allow-bind-keywords t
      org-export-with-author t
      org-format-latex-options (plist-put org-format-latex-options :scale 1.3))

(defvar my/canonical "https://benjamin-james.github.io")

(defvar my/person
  '((@id . (concat my/canonical "/#profile"))
    (@type . "Person")
    (name . "Benjamin James")
    (url  . my/canonical)
    (image . (concat my/canonical "/assets/photo.jpg"))
    (email . "mailto:benjames@mit.edu")
    (affiliation . ((@type . "Organization") (name . "MIT")))
    (sameAs . ["https://www.mit.edu/~benjames"
	       "https://people.csail.mit.edu/benjames"
	       "https://personal.broadinstitute.org/bjames/"
	       "https://github.com/benjamin-james"
	       "https://scholar.google.com/citations?user=t0y3zRkAAAAJ"
               "https://orcid.org/0000-0002-6228-055X"])))

(defun my/jsonld-script (obj)
  (let ((json-encoding-pretty-print t))
    (format "<script type=\"application/ld+json\">%s</script>"
            (json-encode `((@context . "https://schema.org") ,@obj)))))

(defconst my/person-head
  (my/jsonld-script `((@graph . [,@(list my/person)]))))

(defun slurp (path)
  (with-temp-buffer (insert-file-contents path) (buffer-string)))


(defun my/org-file->html-fragment (path)
  "Return body-only HTML for the Org file at PATH, or empty string if missing."
  (if (and path (file-readable-p path))
      (with-temp-buffer
        (insert-file-contents path)
        (org-export-string-as (buffer-string) 'html t
                              '(:with-toc nil :section-numbers nil :validate nil)))
    ""))

(defvar my/html-preamble  (my/org-file->html-fragment "assets/navbar.org"))
(defvar my/html-postamble (my/org-file->html-fragment "assets/postamble.org"))

(defconst my/html-head
  (concat
   "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
   "<link rel=\"stylesheet\" href=\"/assets/water.css\">\n"
   "<link rel=\"stylesheet\" href=\"/assets/overrides.css\">\n"
   my/person-head))

;; latex
(setq org-latex-compiler "xelatex")
(setq org-latex-pdf-process
      '("latexmk -shell-escape -bibtex -f -pdfxe -interaction=nonstopmode -output-directory=%o %f"))

(setq org-publish-project-alist
      `(
        ("site"
         :base-directory "content"
	 :base-extension "org"
	 :recursive t
	 :with-author t
	 :with-email t
	 :section-numbers nil
         :publishing-directory "docs"
         :publishing-function org-html-publish-to-html
         :time-stamp-file nil
         :html-head ,my/html-head
         :html-preamble ,my/html-preamble       
         :html-postamble ,my/html-postamble)
	("cv-pdf"
	 :base-directory "content"
	 :include "cv.org"
	 :publishing-directory "docs/assets"
         :publishing-function org-latex-publish-to-pdf
         :time-stamp-file nil)
        ("assets"
         :base-directory "assets"
         :base-extension "css\\|png\\|jpg\\|svg\\|pdf\\|woff\\|woff2\\|txt\\|ico"
	 :recursive t
         :publishing-directory "docs/assets"
         :publishing-function org-publish-attachment)
        ("site-all" :components ("site" "assets"))))

(defun my/publish () (interactive) (org-publish "site-all" t))
(defun my/clean   () (interactive) (delete-directory "docs" t))

(provide 'publish)
;;; publish.el ends here
