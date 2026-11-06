#!/usr/bin/env python3
# V6 du site Anime Organizer : galerie fidele au logiciel Windows.
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
page=root/'docs/index.html'
if not page.is_file():raise SystemExit('ERREUR: docs/index.html manquant. Veuillez synchroniser le projet GitHub.')
s=page.read_text(encoding='utf-8')
if '<section id="fonctionnalites"' not in s or '</style>' not in s:
 raise SystemExit('Structure du site inconnue. Aucun fichier modifie.')
css='''
/* V6 - Galerie fidele a la vraie version Windows */
.ao-screens{padding:68px 0;background:linear-gradient(140deg,#11171a,#1d181a 64%,#101518);border-block:1px solid #ffffff18}
.ao-screens .eyebrow{color:#f47d64}.ao-screen-main{margin-top:26px}
.ao-screen-grid{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:20px}
.ao-shot{display:block;border:1px solid #4a5054;border-radius:13px;overflow:hidden;background:#101416;box-shadow:0 20px 50px #0007;text-decoration:none}
.ao-shot:hover,.ao-shot:focus-visible{border-color:#ef5d51;transform:translateY(-2px)}
.ao-shot img{display:block;width:100%;height:auto;object-fit:contain}
.ao-shot figcaption{padding:14px 18px;background:#171d20;color:#f3f1ee;font-size:15px}
.ao-shot figcaption small{display:block;color:#b0b6b7;font-size:12px;margin-top:4px}
.ao-note{font-size:13px;color:#b3b9ba;margin-top:18px}
.ao-tag{display:inline-block;background:#b74234;color:#fff;padding:2px 9px;margin-right:6px;border-radius:4px;font-weight:700}
@media(max-width:750px){.ao-screen-grid{grid-template-columns:1fr}.ao-screens{padding:46px 0}}
'''
section='''
<section id="apercus" class="ao-screens">
 <div class="wrap">
  <div class="eyebrow">L'interface en images</div>
  <h2>Découvre Anime Organizer avant de l'installer.</h2>
  <p>Comme dans l'application Windows : une grille d'affiches, des filtres rapides et une fiche détaillée avec fond panoramique. Clique sur une image pour l'agrandir.</p>
  <figure class="ao-shot ao-screen-main"><a href="assets/apercu_bibliotheque.webp" target="_blank" rel="noopener" aria-label="Agrandir l'aperçu de la bibliothèque"><img loading="lazy" src="assets/apercu_bibliotheque.webp" width="1440" height="800" alt="Démonstration de la bibliothèque Windows avec catégories et affiches fictives" /></a><figcaption>Bibliothèque Windows<small>Affiches, catégories, classement et suivi des épisodes.</small></figcaption></figure>
  <div class="ao-screen-grid">
    <figure class="ao-shot"><a href="assets/apercu_fiche.webp" target="_blank" rel="noopener" aria-label="Agrandir la fiche de série"><img loading="lazy" src="assets/apercu_fiche.webp" width="1440" height="800" alt="Fiche de série fictive avec synopsis, image de fond et liste des épisodes" /></a><figcaption>Fiche détaillée<small>Fond illustré, synopsis et accès direct aux épisodes.</small></figcaption></figure>
    <figure class="ao-shot"><a href="assets/apercu_filtres.webp" target="_blank" rel="noopener" aria-label="Agrandir les filtres de la bibliothèque"><img loading="lazy" src="assets/apercu_filtres.webp" width="1420" height="635" alt="Zoom sur les filtres et les catégories de l'application" /></a><figcaption>Navigation et filtres<small>Animés, dessins animés, animation adulte, favoris et progression.</small></figcaption></figure>
  </div>
  <p class="ao-note"><span class="ao-tag">Démo</span> Captures reconstituées à partir du graphisme réel du logiciel, avec des noms et illustrations fictifs. Elles ne constituent pas une capture d'une version en fonctionnement.</p>
 </div>
</section>
'''
# Replace existing V5 block completely if present; V4 can also be patched directly.
if '<section id="apercus"' in s:
 s,n=re.subn(r'<section id="apercus"[^>]*>.*?</section>',section,s,count=1,flags=re.S)
 if n!=1:raise SystemExit('Section apercus non reconnue')
else:
 s=s.replace('<section id="fonctionnalites"',section+'<section id="fonctionnalites"',1)
# Remove V5-specific style (if any), to avoid stale display CSS and duplication.
s=re.sub(r'/\* V5 : galerie demonstrative fidele a la version Windows \*/.*?(?=</style>)','',s,count=1,flags=re.S)
if '/* V6 - Galerie fidele' not in s:s=s.replace('</style>',css+'</style>',1)
if 'href="#apercus">Aperçus' not in s:
 s=s.replace('<a href="#fonctionnalites">Fonctionnalités</a>','<a href="#apercus">Aperçus</a><a href="#fonctionnalites">Fonctionnalités</a>',1)
s=s.replace('href="#fonctionnalites">Découvrir les fonctions','href="#apercus">Voir l’application',1)
page.write_text(s,encoding='utf-8')
print('Site V6 : 3 apercus de demonstration installes.')
