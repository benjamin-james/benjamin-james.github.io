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
      org-export-with-title nil
      org-export-with-date t
      org-export-allow-bind-keywords t
      org-export-with-author t
      org-format-latex-options (plist-put org-format-latex-options :scale 1.3))

(defun my/person (canonical)
  `((@id . ,(concat canonical "/#profile"))
    (@type . "Person")
    (name . "Benjamin James")
    (url  . ,canonical)
    (image . ,(concat canonical "/assets/photo.jpg"))
    (email . "mailto:benjames@mit.edu")
    (jobTitle . "Ph.D candidate")
    (knowsAbout . ["Computational biology"
                   "Single-cell genomics"
                   "Spatial transcriptomics"
                   "Gene regulation"
                   "Computational genomics"])
    (affiliation . ((@type . "CollegeOrUniversity")
                    (name . "MIT")
                    (sameAs . "https://en.wikipedia.org/wiki/Massachusetts_Institute_of_Technology")))
    (memberOf . ((@type . "ResearchOrganization")
                 (name . "MIT CSAIL")
                 (url . "https://www.csail.mit.edu")
                 (sameAs . "https://en.wikipedia.org/wiki/MIT_Computer_Science_and_Artificial_Intelligence_Laboratory")))
    (sameAs . ["https://www.mit.edu/~benjames"
	       "https://people.csail.mit.edu/benjames"
	       "https://personal.broadinstitute.org/bjames/"
	       "https://github.com/benjamin-james"
               "https://benjamin-james.github.io"
	       "https://scholar.google.com/citations?user=t0y3zRkAAAAJ"
	       "https://orcid.org/0000-0002-6228-055X"])))

(defun my/jsonld-script (obj)
  (let ((json-encoding-pretty-print t))
    (format "<script type=\"application/ld+json\">%s</script>"
            (json-encode `((@context . "https://schema.org") ,@obj)))))

(defconst my/canonical
  (or (getenv "SITE_CANONICAL") "https://www.mit.edu/~benjames"))
(defconst my/person-head
  (my/jsonld-script `((@graph . [,@(list (my/person my/canonical))]))))

(defun slurp (path)
  (with-temp-buffer (insert-file-contents path) (buffer-string)))

(defun my/derive-description (info)
  "Derive a ~155-char meta description from the first text paragraph.
Uses #+DESCRIPTION when set; otherwise extracts plain text from the
parse tree's first paragraph by rendering to HTML then stripping tags.
Falls back to the page title when no paragraph text is found."
  (or (plist-get info :description)
      (let ((tree (plist-get info :parse-tree))
            (found nil))
        (org-element-map tree 'paragraph
          (lambda (p)
            (unless found
              (let* ((html (org-export-data p info))
                     (text (replace-regexp-in-string "<[^>]+>" "" html))
                     (text (replace-regexp-in-string "&amp;" "&" text))
                     (text (replace-regexp-in-string "&lt;" "<" text))
                     (text (replace-regexp-in-string "&gt;" ">" text))
                     (text (org-trim
                            (replace-regexp-in-string "\\s-+" " " text))))
                (when (org-string-nw-p text)
                  (setq found
                        (if (> (length text) 155)
                            (concat (substring text 0 152) "…")
                          text)))))))
        (or found
            (let ((title (org-export-data (plist-get info :title) info)))
              (when (org-string-nw-p title)
                (if (> (length title) 155)
                    (concat (substring title 0 152) "…")
                  title)))))))

(defun my/html-meta-tags (info)
  "Emit standard Org meta tags plus an auto-derived description."
  (let ((default (org-html-meta-tags-default info))
        (desc (my/derive-description info)))
    (if (and desc (not (plist-get info :description)))
        (append default (list (list "name" "description" desc)))
      default)))

(setq org-html-meta-tags #'my/html-meta-tags)


(defun my/org-file->html-fragment (path)
  "Return body-only HTML for the Org file at PATH, or empty string if missing."
  (if (and path (file-readable-p path))
      (with-temp-buffer
        (insert-file-contents path)
        (org-export-string-as (buffer-string) 'html t
                              '(:with-toc nil :section-numbers nil :validate nil :with-title nil)))
    ""))

(defvar my/html-preamble  (my/org-file->html-fragment "assets/navbar.org"))
(defvar my/html-postamble (my/org-file->html-fragment "assets/postamble.org"))

(defconst my/og-description
  "PhD candidate in computational biology at MIT CSAIL studying the gene regulatory landscape of human disease using single-cell and spatial omics.")

(defconst my/html-head
  (concat
   "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
   "<link rel=\"canonical\" href=\"" my/canonical "\"/>\n"
   "<link rel=\"icon\" href=\"assets/photo-thumb.jpg\">\n"
   "<link rel=\"stylesheet\" href=\"" my/canonical "/assets/water.css\">\n"
   "<link rel=\"stylesheet\" href=\"" my/canonical "/assets/overrides.css\">\n"
   "<meta property=\"og:type\" content=\"profile\">\n"
   "<meta property=\"og:site_name\" content=\"Benjamin James\">\n"
   "<meta property=\"og:title\" content=\"Benjamin James — Computational Biology, MIT CSAIL\">\n"
   "<meta property=\"og:description\" content=\"" my/og-description "\">\n"
   "<meta property=\"og:url\" content=\"" my/canonical "\">\n"
   "<meta property=\"og:image\" content=\"" my/canonical "/assets/photo.jpg\">\n"
   "<meta name=\"twitter:card\" content=\"summary_large_image\">\n"
   "<meta name=\"twitter:title\" content=\"Benjamin James — Computational Biology, MIT CSAIL\">\n"
   "<meta name=\"twitter:description\" content=\"" my/og-description "\">\n"
   "<meta name=\"twitter:image\" content=\"" my/canonical "/assets/photo.jpg\">\n"
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
        ("assets"
         :base-directory "assets"
         :base-extension "css\\|png\\|jpg\\|svg\\|pdf\\|woff\\|woff2\\|txt\\|ico"
	 :recursive t
         :publishing-directory "docs/assets"
         :publishing-function org-publish-attachment)
        ("root-files"
         :base-directory "root"
         :base-extension "txt"
         :recursive nil
         :publishing-directory "docs"
         :publishing-function org-publish-attachment)
        ("site-all" :components ("site" "assets" "root-files"))))

(defun my/generate-sitemap ()
  "Write docs/sitemap.xml listing every docs/*.html with the canonical base."
  (let* ((base (replace-regexp-in-string "/+$" "" my/canonical))
         (pages (directory-files "docs" t "^index\\.html$"))
         (pages (append pages
                        (cl-remove-if
                         (lambda (f) (string-match "^index\\.html$" (file-name-nondirectory f)))
                         (directory-files "docs" t "\\.html$"))))
         (entries
          (mapconcat
           (lambda (f)
             (let* ((name (file-name-nondirectory f))
                    (loc (concat base "/" name))
                    (mtime (format-time-string "%Y-%m-%d"
                                               (nth 5 (file-attributes f)))))
               (format "  <url>\n    <loc>%s</loc>\n    <lastmod>%s</lastmod>\n    <changefreq>monthly</changefreq>\n    <priority>0.7</priority>\n  </url>"
                       loc mtime)))
           pages "\n")))
    (with-temp-file "docs/sitemap.xml"
      (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
      (insert "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
      (insert entries "\n")
      (insert "</urlset>\n"))))

(defun my/generate-robots ()
  "Write docs/robots.txt allowing all bots and pointing at the sitemap."
  (let ((base (replace-regexp-in-string "/+$" "" my/canonical)))
    (with-temp-file "docs/robots.txt"
      (insert "User-agent: *\nAllow: /\n\n")
      (insert "# Explicitly welcome AI/LLM crawlers\n")
      (insert "User-agent: GPTBot\nAllow: /\n")
      (insert "User-agent: ClaudeBot\nAllow: /\n")
      (insert "User-agent: PerplexityBot\nAllow: /\n")
      (insert "User-agent: Google-Extended\nAllow: /\n")
      (insert "User-agent: CCBot\nAllow: /\n\n")
      (insert (format "Sitemap: %s/sitemap.xml\n" base)))))

(defun my/publish ()
  (interactive)
  (org-publish "site-all" t)
  (my/generate-sitemap)
  (my/generate-robots))
(defun my/clean   () (interactive) (delete-directory "docs" t))

(provide 'publish)
;;; publish.el ends here
