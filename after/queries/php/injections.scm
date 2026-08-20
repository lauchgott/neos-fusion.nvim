;; extends
;;
;; Conservative Tree-sitter injection: Fusion/AFX inside PHP heredocs whose
;; identifier is FUSION or AFX.
;;
;;   $fusion = <<<FUSION
;;   prototype(Vendor.Site:Foo) < prototype(Neos.Fusion:Component) { }
;;   FUSION;
;;
;; Deliberately only this case: a blanket injection into PHP strings would be
;; unreliable and would damage ordinary PHP content. `;; extends` makes sure
;; the standard queries are kept.

((heredoc
   (heredoc_start) @_start
   (heredoc_body) @injection.content)
 (#match? @_start "^(FUSION|AFX)$")
 (#set! injection.language "fusion"))
