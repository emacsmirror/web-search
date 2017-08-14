;;; web-search.el --- Open a web search  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Chunyang Xu

;; Author: Chunyang Xu <mail@xuchunyang.me>
;; Package-Requires: ((seq "1.11") (emacs "24"))
;; Keywords: web, search

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

;; Inspired by https://github.com/zquestz/s

;;; Code:

(require 'seq)

;; XXX Bug of `browse-url'? Encoding problem?
;;
;;   (browse-url "https://github.com/search?utf8=✓&q=hello%20world")
;;
;; will visit     https://github.com/search?utf8=%E2%9C%93&q=hello%2520world instead
;;
;; (noticing "hello%20world" becomes "hello%2520world")

(defvar web-search-providers
  '(
    ;; M-x sort-lines
    ("Bing"              "https://www.bing.com/search?q=%s" "Search")
    ("Debian Manpages"   "https://manpages.debian.org/jump?q=%s")
    ("Emacs China"       "https://emacs-china.org/search?q=%s")
    ("Gist"              "https://gist.github.com/search?q=%s" "Code")
    ("GitHub"            "https://github.com/search?ut&q=%s" "Code")
    ("Google"            "https://www.google.com/search?q=%s" "Search")
    ("Hacker News"       "https://hn.algolia.com/?q=%s" "Tech-News")
    ("MacPorts"          "https://www.macports.org/ports.php?by=name&substr=%s")
    ("Stack Overflow"    "https://stackoverflow.com/search?q=%s" "Code")
    ("Wikipedia"         "https://en.wikipedia.org/wiki/Special:Search?search=%s" "Education")
    ("YouTube"           "https://www.youtube.com/results?search_query=%s")
    ;; M-x sort-lines ends
    ))

(defvar web-search-default-provider "Google")

(defun web-search--tags ()
  (seq-uniq (seq-mapcat #'cddr web-search-providers)))

(defun web-search--find-providers (tag)
  "Return a list of providers which is tagged by TAG."
  (or (seq-filter (lambda (p) (seq-contains (cddr p) tag)) web-search-providers)
      (error "Unknown tag '%s'" tag)))

(defun web-search--format-url (query provider)
  "Format a URL for search QUERY on PROVIDER.
PROVIDER can be a string (the name of one provider) or a
list (one provider, i.e., one element of `web-search-providers')."
  (let ((url (cond
              ((listp provider) (cadr provider))
              ;; XXX Ignore case?
              ((stringp provider) (cadr (assoc provider web-search-providers))))))
    (if url
        (format url (url-hexify-string query))
      (error "Unknown provider '%S'" provider))))

(defun web-search--format-urls (query providers)
  (mapcar (lambda (provider) (web-search--format-url query provider))
          providers))


;;; Commands

;;;###autoload
(defun web-search (query &optional providers tag)
  (interactive
   (let* ((providers
           (if (equal current-prefix-arg '(4)) ; One C-u
               (let* ((default web-search-default-provider)
                      (prompt (format "Provider (default %s): " default)))
                 (list (completing-read prompt web-search-providers nil t nil nil default)))
             (list web-search-default-provider)))
          (tag
           (when (equal current-prefix-arg '(16)) ; Two C-u
             (completing-read "Tag: " (web-search--tags))))
          (query
           (let ((initial (if (use-region-p)
                              (buffer-substring (region-beginning) (region-end))
                            (current-word)))
                 (prompt (format "Search %s for: "
                                 (if tag
                                     (format "about %s on %s" tag
                                             (mapconcat #'identity
                                                        (mapcar #'car
                                                                (web-search--find-providers tag))
                                                        ", "))
                                   (concat "on " (mapconcat #'identity providers ", "))))))
             (read-string prompt initial))))
     (list query providers tag)))
  (setq providers (or (and tag (web-search--find-providers tag))
                      providers
                      (list web-search-default-provider)))
  (mapc #'browse-url (web-search--format-urls query providers)))


;;; Batch

(defun web-search-batch ()
  (unless noninteractive
    (user-error "`web-search-batch' can only be called in batch mode"))

  (setq argv (delete "--" argv))

  (when (or (seq-contains argv "-h")
            (seq-contains argv "--help"))
    (princ (format "\
Web search from the command line.

Usage: emacs -Q --batch -l web-search.el -f web-search-batch -- <query> [options]

Options:
  -h, --help              display help
  -l, --list-providers    list supported providers
      --list-tags         list available tags
  -o, --output            output only mode
  -p, --provider string   search provider (default \"%s\")
  -t, --tag string        search tag
  -v, --verbose           verbose mode
" web-search-default-provider))
    (kill-emacs 0))

  (when (or (seq-contains argv "-l")
            (seq-contains argv "--list-providers"))
    (mapc (lambda (p) (princ (format "%s\n" (car p)))) web-search-providers)
    (kill-emacs 0))

  (when (seq-contains argv "--list-tags")
    (mapc (lambda (s) (princ (format "%s\n" s))) (sort (web-search--tags) #'string<))
    (kill-emacs 0))

  (let (arg
        verbose-mode
        output-only-mode
        query
        provider
        tag
        providers
        urls)
    (while (setq arg (pop argv))
      (pcase arg
        ((or "-v" "--verbose") (setq verbose-mode t))
        ((or "-o" "--output")  (setq output-only-mode t))
        ((or "-p" "--provider") (setq provider (pop argv)))
        ((or "-t" "--tag") (setq tag (pop argv)))
        (_ (setq query (if query
                           (concat query " " arg)
                         arg)))))

    (setq providers (or (and tag (web-search--find-providers tag))
                        (and provider (list provider))
                        (list web-search-default-provider)))
    (setq urls (web-search--format-urls query providers))
    (when (or verbose-mode output-only-mode)
      (mapc (lambda (url) (princ (format "%s\n" url))) urls))
    (unless output-only-mode
      (mapc (lambda (url)
              (let ((rtv (browse-url url)))
                (when (processp rtv)
                  (accept-process-output (browse-url url)))))
            urls))))

(provide 'web-search)
;;; web-search.el ends here
