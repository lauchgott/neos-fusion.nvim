;; extends
;;
;; Konservative Tree-sitter-Injection: Fusion/AFX in PHP-Heredocs, deren
;; Bezeichner FUSION oder AFX lautet.
;;
;;   $fusion = <<<FUSION
;;   prototype(Vendor.Site:Foo) < prototype(Neos.Fusion:Component) { }
;;   FUSION;
;;
;; Bewusst nur dieser Fall: eine pauschale Injection in PHP-Strings waere
;; unzuverlaessig und wuerde normale PHP-Inhalte beschaedigen. `;; extends`
;; sorgt dafuer, dass die Standard-Queries erhalten bleiben.

((heredoc
   (heredoc_start) @_start
   (heredoc_body) @injection.content)
 (#match? @_start "^(FUSION|AFX)$")
 (#set! injection.language "fusion"))
